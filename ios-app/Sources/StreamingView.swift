import SwiftUI
import AVFoundation

/// Full-screen live view shown while streaming. Two layers over the
/// camera preview (docs/UI_DESIGN.md §6.2): the **glance layer** — status
/// pill, Pause, Stop, the lens buttons and a chevron — which is the whole
/// screen for most of a stream, and the **adjust tray** the chevron opens,
/// where every manual control shares one dial retargeted by a chip row.
/// Once the idle fuse burns down, whichever idle view the user picked
/// (Options → Idle view) takes over: controls left up, a clean feed, or a
/// dimmed screen.
struct StreamingView: View {
    @EnvironmentObject private var streamer: Streamer

    /// The idle view is engaged: the fuse burned down (or the idle
    /// action was tapped) and `idleAppearance` is doing whatever it does.
    /// Never true for `.standard`, which has no idle view.
    @State private var idle = false
    @State private var lastInteraction = Date()
    @State private var pinchBaseZoom: CGFloat = 1
    /// Exposure bias when the one-finger drag began; nil while no drag
    /// is in flight. Doubles as the "show the EV readout" switch.
    @State private var dragBaseBias: Float?
    @State private var previousBrightness: CGFloat = UIScreen.main.brightness
    /// Whether `previousBrightness` is a level we still owe the system.
    /// Tracked rather than derived from the current mode: the mode can
    /// change while the screen is dimmed, and the restore must survive it.
    @State private var brightnessLowered = false
    /// The adjust tray is up in place of the lens buttons.
    @State private var trayOpen = false
    /// Which parameter the tray's dial drives.
    @State private var dialTarget: DialTarget = .exposure
    /// Each back lens's magnification relative to Main, for the lens
    /// buttons' labels. Read once per stream: it walks the device list.
    @State private var lensFactors: [String: Double] = [:]
    /// Stream health pill (fps · Mb/s · dropped). Persisted: someone who
    /// turns it on is debugging and wants it next stream too. The streamer
    /// reads the same key to decide whether to sample health at all.
    @AppStorage(StreamerDefaults.showHealth) private var showHealth = false
    /// Battery level for the dim readout and the low-battery tally.
    /// Monitoring runs only while this screen is up (see .task below).
    @ObservedObject private var battery = BatteryMonitor.shared

    private static let idleAfterSeconds: TimeInterval = 10

    /// How far one screen-height of drag moves exposure bias. Six stops
    /// end to end: fine enough to land on a third of a stop, coarse
    /// enough that a thumb's worth of travel visibly does something.
    private static let dragStopsPerScreen: Float = 6

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CameraPreviewView(
                session: streamer.camera.session,
                sessionQueue: streamer.camera.sessionQueue,
                videoGravity: .resizeAspect,
                // Battery saver: while the dim overlay hides everything,
                // stop rendering preview frames too (the stream to OBS is
                // untouched). The last frame freezes underneath, invisible
                // behind the overlay.
                previewEnabled: !dimmed,
                onTapAtDevicePoint: { point in
                    touched()
                    // Via the streamer so a tap keeps manual exposure locked.
                    streamer.focusAndExpose(at: point)
                },
                onPinchZoom: { phase, scale in
                    touched()
                    // Re-anchor at gesture start: zoom may have moved via
                    // the dial or a remote command since the last pinch,
                    // and a stale base makes the next pinch jump.
                    if phase == .began {
                        pinchBaseZoom = streamer.zoom
                    }
                    streamer.zoom = min(
                        max(pinchBaseZoom * scale, 1),
                        streamer.camera.maxZoomFactor)
                },
                onVerticalDrag: { phase, travel in
                    verticalDrag(phase, travel: travel)
                }
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                if showsControls {
                    statusBar
                    noticeRow
                }
                // Survives the clean feed when Stats is on: numbers are a
                // readout, not a control, and Stats is exactly the
                // "optionally, with health" switch (docs/UI_DESIGN.md
                // §6.2). Hidden under the dim overlay, which covers it.
                if showHealth, !dimmed, let health = streamer.health {
                    healthPill(health)
                }
                Spacer()
                if showsControls {
                    if trayOpen {
                        adjustTray
                    } else {
                        glanceControls
                    }
                }
            }
            .padding()
            .animation(.easeInOut(duration: 0.2), value: showsControls)
            .animation(.easeInOut(duration: 0.2), value: trayOpen)

            // The drag's readout, centred where the eye already is. Only
            // while a finger is down: a value that lingers reads as a
            // control, and it isn't one.
            if dragBaseBias != nil {
                Text(readout(.exposure))
                    .font(.system(size: 17, weight: .semibold,
                                  design: .rounded).monospacedDigit())
                    .foregroundColor(Theme.cameraYellow)
                    .glassPill()
                    .allowsHitTesting(false)
            }

            if dimmed {
                dimOverlay
            }
            if cleanFeed {
                // Invisible tap catcher over the whole clean feed: the
                // first tap only brings the controls back, so waking is
                // never also a focus pull at wherever your thumb landed
                // — and the letterbox bars, which the preview's own
                // recognizer never sees, wake it too.
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    // Touch-down, not tap: a pinch starting on the clean
                    // feed must wake it too, and a tap gesture fails the
                    // moment the fingers move. Safe here where a drag
                    // would not be on the settings form (#96/#97) — this
                    // layer covers no controls and is gone the instant
                    // it fires.
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { _ in touched() })
            }

            // Above the dim overlay on purpose: a phone mounted out of
            // reach dims itself after ten seconds, and that is exactly
            // when knowing you're on air matters most.
            tallyBorder
        }
        .statusBar(hidden: true)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if streamer.idleAppearance != .standard && !idle &&
                    Date().timeIntervalSince(lastInteraction)
                        > Self.idleAfterSeconds {
                    goIdle()
                }
            }
        }
        // The preference is only reachable from the Setup screen today,
        // but a change arriving under a live idle view (an App Intent, a
        // future remote command) must not strand the screen dark or
        // control-less in a mode that no longer applies.
        .onChange(of: streamer.idleAppearance) { _ in wake() }
        // Battery monitoring is a device-wide flag, so it is held only
        // while this screen exists — the Setup screen has nothing to show.
        .onAppear {
            battery.retain()
            refreshLensFactors()
        }
        .onDisappear {
            battery.release()
            restoreBrightness()
        }
    }

    /// True while the controls are on screen: always in Standard, and in
    /// the other modes until the fuse burns down.
    private var showsControls: Bool { !idle }

    /// The clean feed is up — preview (plus tally, plus the health pill
    /// if Stats is on) and nothing else.
    private var cleanFeed: Bool { idle && streamer.idleAppearance == .clean }

    /// The dim overlay is up.
    private var dimmed: Bool { idle && streamer.idleAppearance == .dim }

    /// Any interaction restarts the fuse and, if an idle view is up,
    /// brings the controls back.
    private func touched() {
        lastInteraction = Date()
        if idle { wake() }
    }

    /// Engages the chosen idle view. Standard has none, so this is a
    /// no-op there (its menu item isn't drawn either).
    private func goIdle() {
        guard streamer.idleAppearance != .standard else { return }
        if streamer.idleAppearance == .dim && !brightnessLowered {
            previousBrightness = UIScreen.main.brightness
            brightnessLowered = true
            UIScreen.main.brightness = 0.05
        }
        withAnimation { idle = true }
    }

    /// Back to the controls.
    private func wake() {
        restoreBrightness()
        withAnimation { idle = false }
        lastInteraction = Date()
    }

    /// Puts the brightness back exactly once, and only if we lowered it —
    /// writing a stale level over one the user (or iOS auto-brightness)
    /// has since changed is its own bug.
    private func restoreBrightness() {
        guard brightnessLowered else { return }
        brightnessLowered = false
        UIScreen.main.brightness = previousBrightness
    }

    /// The Camera app's sun slider: one finger up or down on the picture
    /// nudges exposure bias, so the tray stays closed for the adjustment
    /// people make most mid-stream. Inert in manual exposure, where bias
    /// has no meaning — ISO and shutter are the dial's job there.
    private func verticalDrag(_ phase: CameraPreviewView.PinchPhase,
                              travel: CGFloat) {
        guard streamer.exposureSetting == .auto else { return }
        touched()
        switch phase {
        case .began:
            dragBaseBias = streamer.exposureBias
        case .changed:
            guard let base = dragBaseBias else { return }
            let range = streamer.camera.exposureBiasRange
            let bias = base + Float(travel) * Self.dragStopsPerScreen
            streamer.exposureBias =
                min(max(bias, range.lowerBound), range.upperBound)
        case .ended:
            dragBaseBias = nil
        }
    }

    private var dimOverlay: some View {
        ZStack {
            // Near-black overlay: real battery savings on OLED, and the
            // brightness drop covers LCDs.
            Color.black.opacity(0.96).ignoresSafeArea()
            VStack(spacing: Theme.Space.m) {
                Image(systemName: "video.fill")
                    .foregroundColor(.green.opacity(0.6))
                Text("Streaming — tap to wake")
                    .font(.footnote)
                    .foregroundColor(.gray)
                batteryReadout
                    .padding(.top, Theme.Space.s)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { wake() }
    }

    /// "Do I need to plug this in?" answered without waking the screen —
    /// the whole point of a phone that dims itself on a stand for an hour.
    /// Deliberately the largest thing on the dimmed screen: the phone it
    /// answers for is across the room on a stand, so the readout has to
    /// carry at that distance, where the footnote-sized row it replaced
    /// did not. Charging shows a bolt; low (Low Power Mode, or 20% and
    /// falling) turns it red. Monospaced digits so a 5% step doesn't
    /// shuffle the row. Nothing renders where iOS won't report a level,
    /// rather than a placeholder that looks like a fault.
    @ViewBuilder private var batteryReadout: some View {
        if let percent = battery.percent {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: batterySymbol(percent))
                    .font(.system(size: 44, weight: .regular))
                Text("\(percent)%")
                    .font(.system(size: 44, weight: .semibold,
                                  design: .rounded).monospacedDigit())
                if battery.isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 30, weight: .semibold))
                }
            }
            .foregroundColor(batteryTint)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(batteryAccessibilityLabel(percent))
        }
    }

    /// VoiceOver reads the level as a sentence; the glyph and the bolt are
    /// decoration once the percentage is spoken.
    private func batteryAccessibilityLabel(_ percent: Int) -> String {
        battery.isCharging
            ? "Battery \(percent) percent, charging"
            : "Battery \(percent) percent"
    }

    /// Red means low, amber means the OS is throttling, grey means fine —
    /// the palette's own reading of each (docs/UI_DESIGN.md §2). Splitting
    /// them matters: Low Power Mode can be switched on at 80%, and a red
    /// readout there would be a lie you learn to ignore.
    private var batteryTint: Color {
        // A brighter grey than the wake hint above it: at 5% brightness
        // under a near-black overlay, `.gray` reads as almost nothing.
        guard !battery.isCharging else { return Color(white: 0.75) }
        if let percent = battery.percent, percent <= 20 {
            return Theme.errorRed
        }
        return battery.lowPowerMode ? Theme.connectAmber
                                    : Color(white: 0.75)
    }

    /// The system battery glyph nearest the real level, so the icon reads
    /// at a glance from across the room even before the number does.
    private func batterySymbol(_ percent: Int) -> String {
        switch percent {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }

    /// Tally: a border round the whole screen, readable at arm's length
    /// from behind a monitor where a small dot wouldn't be. Which statuses
    /// light it, in which colours and priority order, is the user's call
    /// (Options → Tally light); the defaults are red on air, amber in
    /// preview, nothing otherwise — an unlit tally has to be as
    /// unambiguous as a lit one.
    @ObservedObject private var tallySettings = TallySettings.shared

    /// Everything currently true about the stream, for the priority list
    /// to pick from.
    private var activeTallyStatuses: Set<TallyStatus> {
        var active: Set<TallyStatus> = []
        switch streamer.tally {
        case .live: active.insert(.onAir)
        case .preview: active.insert(.preview)
        case .off: break
        }
        // Mid-stream link drop: the client auto-reconnects (status flips
        // to .connecting) or died outright (.error). Either way the phone
        // is capturing into a void, which is worth a glance-able warning
        // if the user assigned one.
        if streamer.isStreaming {
            if case .error = streamer.status {
                active.insert(.connectionLost)
            } else if streamer.status == .connecting {
                active.insert(.connectionLost)
            }
        }
        switch streamer.syncState {
        case .measuring, .relocking: active.insert(.calibrating)
        case .locked: active.insert(.syncLocked)
        case .off: break
        }
        // The stream outliving the battery is a production failure like
        // any other, and the phone is usually out of reach when it starts
        // going wrong — so it gets the same border vocabulary, off by
        // default like every other informational status.
        if battery.isLow {
            active.insert(.lowBattery)
        }
        return active
    }

    @ViewBuilder private var tallyBorder: some View {
        if let light = tallySettings.activeLight(for: activeTallyStatuses) {
            // On air keeps the heaviest stroke; everything informational
            // stays lighter so live remains the most emphatic state even
            // in user-chosen colours.
            tallyEdge(light.color,
                      width: light.entry.status == .onAir ? 6 : 4,
                      pulse: light.entry.pulse)
        } else {
            EmptyView()
        }
    }

    /// Corner radius for the tally border. Modern iPhones have rounded
    /// display corners that physically clip a sharp-cornered stroke, so the
    /// border visibly broke at all four corners. There's no public API for
    /// the exact panel radius; a generous continuous curve covers every
    /// current device (their radii run ~40–55 pt) and errs by curving
    /// slightly *inside* the corner rather than getting cut off. Squared
    /// devices (SE, iPads) are detected by their zero bottom safe-area
    /// inset and keep square corners.
    private static let tallyCornerRadius: CGFloat = {
        let bottomInset = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.windows.first }
            .first?.safeAreaInsets.bottom ?? 0
        return bottomInset > 0 ? 58 : 0
    }()

    private func tallyEdge(_ colour: Color, width: CGFloat,
                           pulse: Bool) -> some View {
        TallyEdge(colour: colour, width: width, pulse: pulse,
                  cornerRadius: Self.tallyCornerRadius)
    }

    // MARK: - Top bar

    /// Three things: status, Pause, Stop. Stats and the idle action moved
    /// into the status pill's menu — both are about the screen, not the
    /// shot, and neither is touched during a stream often enough to earn
    /// a button of its own.
    private var statusBar: some View {
        HStack(spacing: Theme.Space.m) {
            statusMenu

            Spacer()

            // Hold the stream without ending it. Amber while paused —
            // the status vocabulary's colour for "connected but not
            // live" — so a glance at the row says which state it's in.
            // Hidden for a camera-side pause: iOS took the camera, and
            // a resume button that can't resume anything is a lie.
            if !streamer.isPaused || streamer.pauseReason == .user {
                ControlButton(systemImage: streamer.isPaused
                                ? "play.fill" : "pause.fill",
                              active: streamer.isPaused) {
                    touched()
                    streamer.setPaused(!streamer.isPaused, reason: .user)
                }
            }

            Button {
                streamer.stop()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: Theme.controlButton, height: Theme.controlButton)
                    .background(Theme.errorRed.opacity(0.9), in: Circle())
            }
        }
        .foregroundColor(Theme.textPrimary)
    }

    /// The status pill is also a menu: Stats on or off, and — in Clean
    /// feed or Dim screen — the idle view now, instead of waiting out
    /// the fuse. The small chevron is what says it opens.
    private var statusMenu: some View {
        Menu {
            Button {
                touched()
                showHealth.toggle()
            } label: {
                Label("Stats", systemImage: showHealth ? "checkmark" : "gauge")
            }
            if streamer.idleAppearance != .standard {
                Button {
                    goIdle()
                } label: {
                    Label(streamer.idleAppearance == .clean
                            ? "Clean feed now" : "Dim screen now",
                          systemImage: streamer.idleAppearance == .clean
                            ? "eye.slash" : "moon.fill")
                }
            }
        } label: {
            HStack(spacing: Theme.Space.s) {
                Circle()
                    .fill(streamer.status.tint)
                    .frame(width: 8, height: 8)
                Text(streamer.status.displayName)
                    .font(.footnote.bold())
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(Theme.textSecondary)
            }
            .foregroundColor(Theme.textPrimary)
            .glassPill()
        }
    }

    /// One row under the status bar for whatever needs saying, most
    /// urgent first: a paused preset you can resume beats a sync readout
    /// you can only watch. Nothing is drawn when there is nothing to say.
    @ViewBuilder private var noticeRow: some View {
        if streamer.canResumePresets {
            presetsPausedPill
        } else if syncLabel != nil {
            syncPill
        }
    }

    /// Lip-sync calibration, shown only while it has something to say —
    /// nothing appears unless auto-calibrate is running in OBS. Wording and
    /// colours come from docs/UI_DESIGN.md and match the web panel's pill.
    private var syncLabel: (text: String, colour: Color)? {
        switch streamer.syncState {
        case .off:
            return nil
        case .measuring:
            return ("Measuring sync", Theme.accent)
        case .locked:
            return ("Sync locked", Theme.liveGreen)
        case .relocking:
            return ("Recalibrating", Theme.connectAmber)
        }
    }

    /// Tapping while locked asks the plugin to throw away the measured mic
    /// latency and calibrate afresh — for when you changed audio gear and
    /// don't want to wait for the periodic check to notice. The arrow only
    /// appears when the tap does something.
    private var syncPill: some View {
        HStack {
            Button {
                touched()
                streamer.requestRecalibrate()
            } label: {
                HStack(spacing: Theme.Space.s) {
                    if let sync = syncLabel {
                        Circle()
                            .fill(sync.colour)
                            .frame(width: 8, height: 8)
                        Text(sync.text)
                            .font(.caption)
                            .lineLimit(1)
                        if streamer.syncState == .locked {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption2)
                        }
                    }
                }
                .glassPill()
                .foregroundColor(Theme.textSecondary)
            }
            .disabled(streamer.syncState != .locked)
            Spacer()
        }
        .padding(.top, Theme.Space.s)
    }

    /// Auto-apply went on hold because a setting was changed by hand, and
    /// this camera has a preset that would otherwise be running. Tapping
    /// re-arms it and applies that preset now — mid-stream, no restart,
    /// which is the whole point (#107). Same pill anatomy as the sync
    /// row's, because it is the same kind of thing: a state you can act on.
    private var presetsPausedPill: some View {
        HStack {
            Button {
                touched()
                streamer.resumePresets()
            } label: {
                HStack(spacing: Theme.Space.s) {
                    Circle()
                        .fill(Theme.connectAmber)
                        .frame(width: 8, height: 8)
                    Text("Presets paused")
                        .font(.caption)
                        .lineLimit(1)
                    Image(systemName: "arrow.clockwise")
                        .font(.caption2)
                }
                .glassPill()
                .foregroundColor(Theme.textSecondary)
            }
            Spacer()
        }
        .padding(.top, Theme.Space.s)
    }

    /// One-line health readout under the status bar: encoder output rate,
    /// wire bitrate, and frames dropped by backpressure this stream. All
    /// values come from counters the client keeps anyway (docs/ROADMAP.md
    /// "stream health overlay"); monospaced so they don't jitter.
    private func healthPill(_ health: Streamer.StreamHealth) -> some View {
        HStack {
            Text("\(health.fps) fps · "
                 + String(format: "%.1f", health.megabitsPerSecond)
                 + " Mb/s · \(health.droppedFrames) dropped")
                .font(.caption.monospacedDigit())
                .glassPill()
            Spacer()
        }
        .padding(.top, Theme.Space.s)
        .foregroundColor(Theme.textPrimary)
    }

    // MARK: - Glance layer

    /// What sits at the bottom of the screen while the tray is closed:
    /// the lens buttons (back cameras only, as in the Camera app) and the
    /// chevron that opens the tray.
    private var glanceControls: some View {
        VStack(spacing: Theme.Space.l) {
            if streamer.selectedLens.position == .back, backLenses.count > 1 {
                lensButtons
            }
            Button {
                touched()
                trayOpen = true
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                    .frame(width: 56, height: 30)
                    .background(Theme.glassChip, in: Capsule())
            }
            .accessibilityLabel("Adjust camera")
        }
    }

    private var backLenses: [CameraManager.Lens] {
        streamer.availableLenses.filter { $0.position == .back }
    }

    private func refreshLensFactors() {
        var factors: [String: Double] = [:]
        for lens in backLenses {
            factors[lens.id] = CameraManager.zoomFactorRelativeToMain(lens)
        }
        lensFactors = factors
    }

    /// The Camera app's lens row: one round button per back lens, the
    /// active one larger and yellow with the live zoom on it, so ".5 · 1× ·
    /// 2" reads exactly as it does in the app everyone already knows.
    /// Tapping switches the physical lens; pinching still zooms within it.
    private var lensButtons: some View {
        HStack(spacing: Theme.Space.s) {
            ForEach(backLenses) { lens in
                let active = lens == streamer.selectedLens
                Button {
                    touched()
                    streamer.selectedLens = lens
                } label: {
                    Text(lensButtonLabel(lens, active: active))
                        .font(.system(size: active ? 13 : 11, weight: .bold,
                                      design: .rounded).monospacedDigit())
                        .foregroundColor(active ? Theme.cameraYellow
                                                : Theme.textPrimary.opacity(0.85))
                        .frame(width: active ? 38 : 32,
                               height: active ? 38 : 32)
                        .background(Color.black.opacity(active ? 0.6 : 0.45),
                                    in: Circle())
                }
                .accessibilityLabel(lens.label)
            }
        }
    }

    /// ".5", "2", "3" for an inactive lens; the active one carries its
    /// real magnification including any pinch zoom ("1×", "2.4×", "0.5×").
    private func lensButtonLabel(_ lens: CameraManager.Lens,
                                 active: Bool) -> String {
        let factor = lensFactors[lens.id] ?? 1
        if active {
            return Self.compactFactor(factor * Double(streamer.zoom)) + "×"
        }
        let text = Self.compactFactor(factor)
        // Camera app spelling: the ultra-wide is ".5", not "0.5".
        return text.hasPrefix("0.") ? String(text.dropFirst()) : text
    }

    /// Two significant figures, no trailing zeros: 1, 0.5, 2.4, 12.
    private static func compactFactor(_ value: Double) -> String {
        String(format: "%.2g", value)
    }

    // MARK: - Adjust tray

    /// What the dial can drive. The chip row shows the ones this camera
    /// has: Shutter needs manual exposure, WB needs a lockable white
    /// balance, Subject exists only while green screen runs with depth.
    private enum DialTarget: Hashable {
        case zoom, exposure, shutter, whiteBalance, focus, subject
    }

    private var dialTargets: [DialTarget] {
        var targets: [DialTarget] = [.zoom, .exposure]
        if streamer.camera.supportsManualExposure { targets.append(.shutter) }
        if streamer.camera.supportsWhiteBalanceLock { targets.append(.whiteBalance) }
        targets.append(.focus)
        if streamer.greenScreenDepthActive { targets.append(.subject) }
        return targets
    }

    /// The chosen target, or Exposure if what was chosen has since gone
    /// away (Subject vanishes when depth assist stops).
    private var activeTarget: DialTarget {
        dialTargets.contains(dialTarget) ? dialTarget : .exposure
    }

    /// One dial, several parameters. The chips say which; a yellow A on a
    /// chip means that parameter is on auto, dragging the dial takes it
    /// manual, and tapping the active chip again hands it back to auto.
    /// Zoom has no auto, and Exposure on auto is the bias dial — an
    /// auto-exposure control, so dragging it leaves auto alone.
    private var adjustTray: some View {
        VStack(spacing: Theme.Space.m) {
            chipRow
            dial
            HStack(spacing: Theme.Space.s) {
                Text(modeLine(activeTarget))
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(2)
                Spacer(minLength: Theme.Space.s)
                if streamer.camera.hasFlashlight {
                    ControlButton(systemImage: streamer.flashlightOn
                                    ? "bolt.fill" : "bolt.slash",
                                  active: streamer.flashlightOn) {
                        touched()
                        streamer.flashlightOn.toggle()
                    }
                }
                ControlButton(
                    systemImage: "arrow.triangle.2.circlepath.camera") {
                    touched()
                    streamer.flipCamera()
                }
                ControlButton(systemImage: "chevron.down") {
                    touched()
                    trayOpen = false
                }
            }
        }
        .tint(Theme.cameraYellow)
        .glassPanel()
        .foregroundColor(Theme.textPrimary)
    }

    private var chipRow: some View {
        HStack(spacing: Theme.Space.xs + 2) {
            ForEach(dialTargets, id: \.self) { target in
                chip(target)
            }
        }
    }

    private func chip(_ target: DialTarget) -> some View {
        let selected = target == activeTarget
        let auto = isAuto(target)
        return Button {
            touched()
            if selected, auto == false {
                setAuto(target)
            } else {
                dialTarget = target
            }
        } label: {
            Text(chipLabel(target))
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundColor(selected ? .black : Theme.textPrimary.opacity(0.8))
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(selected ? Color.white : Theme.glassChip,
                            in: Capsule())
                .overlay(alignment: .topTrailing) {
                    if auto == true {
                        Text("A")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundColor(selected ? Theme.cameraYellow : .black)
                            .frame(width: 13, height: 13)
                            .background(selected ? Color.black : Theme.cameraYellow,
                                        in: Circle())
                            .offset(x: 2, y: -5)
                    }
                }
        }
        .accessibilityLabel(chipAccessibilityLabel(target, auto: auto))
    }

    private func chipAccessibilityLabel(_ target: DialTarget, auto: Bool?) -> String {
        let name = chipLabel(target)
        switch auto {
        case nil: return name
        case true?: return "\(name), auto"
        case false?: return "\(name), manual"
        }
    }

    private func chipLabel(_ target: DialTarget) -> String {
        switch target {
        case .zoom: return "Zoom"
        // The same chip drives bias on auto and ISO in manual; its name
        // follows, so the dial's readout and the chip never disagree.
        case .exposure:
            return streamer.exposureSetting == .manual ? "ISO" : "Exposure"
        case .shutter: return "Shutter"
        case .whiteBalance: return "WB"
        case .focus: return "Focus"
        case .subject: return "Subject"
        }
    }

    /// nil where the parameter has no auto (zoom); for Subject, "auto" is
    /// no cutoff — the "All" the old readout tapped back to.
    private func isAuto(_ target: DialTarget) -> Bool? {
        switch target {
        case .zoom: return nil
        case .exposure, .shutter: return streamer.exposureSetting == .auto
        case .whiteBalance: return streamer.whiteBalanceSetting == .auto
        case .focus: return streamer.focusSetting == .auto
        case .subject: return streamer.greenScreenMaxDistance == 0
        }
    }

    private func setAuto(_ target: DialTarget) {
        switch target {
        case .zoom: break
        case .exposure, .shutter: streamer.exposureSetting = .auto
        case .whiteBalance: streamer.whiteBalanceSetting = .auto
        case .focus: streamer.focusSetting = .auto
        case .subject: streamer.greenScreenMaxDistance = 0
        }
    }

    /// A drag on the dial means "I want this by hand": the first touch
    /// takes the parameter out of auto, so the value the finger sets is
    /// the value the camera keeps. Bias and zoom have no manual to enter;
    /// Subject's binding sets a cutoff by itself.
    private func engageManual(_ target: DialTarget) {
        switch target {
        case .zoom, .exposure, .subject: break
        case .shutter:
            if streamer.exposureSetting == .auto {
                streamer.exposureSetting = .manual
            }
        case .whiteBalance:
            if streamer.whiteBalanceSetting == .auto {
                streamer.whiteBalanceSetting = .locked
            }
        case .focus:
            if streamer.focusSetting == .auto {
                streamer.focusSetting = .locked
            }
        }
    }

    private func modeLine(_ target: DialTarget) -> String {
        switch target {
        case .zoom:
            return "Pinch the picture to zoom"
        case .exposure where streamer.exposureSetting == .auto:
            return "Auto · drag the picture up or down"
        case .subject:
            return streamer.greenScreenMaxDistance > 0
                ? "Cutoff · tap Subject for all"
                : "All · drag to set a cutoff"
        default:
            return isAuto(target) == true
                ? "Auto · drag to set by hand"
                : "Manual · tap \(chipLabel(target)) for auto"
        }
    }

    /// The dial: readout above, slider below, both in the camera yellow.
    /// A native slider rather than a drawn ruler — it tracks the finger
    /// with no lag (docs/UI_DESIGN.md §7) and VoiceOver already knows it.
    private var dial: some View {
        VStack(spacing: Theme.Space.xs) {
            Text(readout(activeTarget))
                .font(.system(size: 15, weight: .bold,
                              design: .rounded).monospacedDigit())
                .foregroundColor(Theme.cameraYellow)
            dialSlider(activeTarget)
        }
    }

    @ViewBuilder private func dialSlider(_ target: DialTarget) -> some View {
        switch target {
        case .zoom:
            slider($streamer.zoom,
                   in: 1...max(streamer.camera.maxZoomFactor, 1.1),
                   target: target)
        case .exposure:
            if streamer.exposureSetting == .manual {
                slider(floatBinding($streamer.iso), in: isoRange, target: target)
            } else {
                slider(floatBinding($streamer.exposureBias), in: exposureRange,
                       target: target)
            }
        case .shutter:
            // Log scale: shutter steps are multiplicative (1/60 → 1/125
            // → 1/250…); a linear slider crams everything usable into
            // its first pixels.
            slider(shutterBinding, in: 0...1, target: target)
        case .whiteBalance:
            slider(floatBinding($streamer.whiteBalanceTemperature),
                   in: 2500...8000, target: target)
        case .focus:
            slider(floatBinding($streamer.lensPosition), in: 0...1,
                   target: target)
        case .subject:
            slider(subjectDistanceBinding, in: 0.5...5.0, target: target)
        }
    }

    private func slider<V>(_ value: Binding<V>, in range: ClosedRange<V>,
                           target: DialTarget) -> some View
        where V: BinaryFloatingPoint, V.Stride: BinaryFloatingPoint {
        Slider(value: value, in: range) { editing in
            if editing {
                touched()
                engageManual(target)
            }
        }
    }

    private func readout(_ target: DialTarget) -> String {
        switch target {
        case .zoom:
            return String(format: "%.1f×", streamer.zoom)
        case .exposure:
            return streamer.exposureSetting == .manual
                ? "ISO \(Int(streamer.iso))"
                : String(format: "%+.1f EV", streamer.exposureBias)
        case .shutter:
            return streamer.exposureSetting == .manual ? shutterReadout : "Auto"
        case .whiteBalance:
            return streamer.whiteBalanceSetting == .locked
                ? "\(Int(streamer.whiteBalanceTemperature)) K" : "Auto"
        case .focus:
            return streamer.focusSetting == .locked
                ? String(format: "%.2f", streamer.lensPosition) : "Auto"
        case .subject:
            return streamer.greenScreenMaxDistance > 0
                ? String(format: "%.1f m", streamer.greenScreenMaxDistance)
                : "All"
        }
    }

    /// The slider's projection of the 0-means-All model value: while
    /// "All", the thumb parks at the far end (everything in reach is
    /// subject); any drag sets a real cutoff.
    private var subjectDistanceBinding: Binding<Double> {
        Binding(
            get: {
                streamer.greenScreenMaxDistance > 0
                    ? streamer.greenScreenMaxDistance : 5.0
            },
            set: { value in
                // Re-round despite the slider's step: float dust would
                // jitter the readout and the STATE snapshot.
                streamer.greenScreenMaxDistance = (value * 10).rounded() / 10
            })
    }

    private var isoRange: ClosedRange<CGFloat> {
        // One line: a leading "..." on a continuation line parses as a
        // separate prefix-range statement, not as this range.
        let range = streamer.camera.isoRange
        let upper = CGFloat(max(range.upperBound, range.lowerBound + 1))
        return CGFloat(range.lowerBound)...upper
    }

    /// Maps shutterSeconds onto a 0…1 log-scale slider position, with
    /// left = long/slow (more light) and right = short/fast.
    private var shutterBinding: Binding<Double> {
        let minSeconds = max(streamer.camera.minShutterSeconds, 1.0 / 8000)
        let maxSeconds = max(
            streamer.camera.maxShutterSeconds(fps: Int32(streamer.fps)),
            minSeconds * 2)
        let logMin = log(minSeconds)
        let logMax = log(maxSeconds)
        return Binding(
            get: {
                let seconds = min(max(streamer.shutterSeconds, minSeconds),
                                  maxSeconds)
                return 1 - (log(seconds) - logMin) / (logMax - logMin)
            },
            set: { position in
                streamer.shutterSeconds =
                    exp(logMax - position * (logMax - logMin))
            })
    }

    private var shutterReadout: String {
        let seconds = streamer.shutterSeconds
        guard seconds < 1 else { return String(format: "%.0fs", seconds) }
        return "1/\(Int((1 / seconds).rounded()))"
    }

    private var exposureRange: ClosedRange<CGFloat> {
        let r = streamer.camera.exposureBiasRange
        return CGFloat(r.lowerBound)...CGFloat(r.upperBound)
    }

    /// Bridges a Float model value to the CGFloat sliders.
    private func floatBinding(_ source: Binding<Float>) -> Binding<CGFloat> {
        Binding(get: { CGFloat(source.wrappedValue) },
                set: { source.wrappedValue = Float($0) })
    }
}

/// The tally border itself. A view of its own, not a function, because a
/// pulse needs somewhere to keep its phase — and re-deriving that phase on
/// every parent re-render (the Live screen redraws on any published
/// change) would restart the animation several times a second.
private struct TallyEdge: View {
    let colour: Color
    let width: CGFloat
    let pulse: Bool
    let cornerRadius: CGFloat

    /// Honour the system's motion setting: someone who asked for less
    /// animation gets a steady border in their chosen colour rather than
    /// no warning at all.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var dimmedPhase = false

    private var pulsing: Bool { pulse && !reduceMotion }

    var body: some View {
        // allowsHitTesting(false): the border sits over the preview, and
        // tap-to-focus near the screen edge must still reach it.
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(colour, lineWidth: width)
            // Never all the way out: a border that vanishes on the dark
            // half of its cycle reads as "no tally" to anyone glancing at
            // the wrong moment.
            .opacity(dimmedPhase ? 0.3 : 1)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.15), value: colour)
            .animation(pulsing
                       ? .easeInOut(duration: 0.9).repeatForever(
                            autoreverses: true)
                       : .easeInOut(duration: 0.2),
                       value: dimmedPhase)
            .onAppear { dimmedPhase = pulsing }
            .onChange(of: pulsing) { on in dimmedPhase = on }
    }
}
