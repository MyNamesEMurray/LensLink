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
    /// The level we still owe the system, and the screen we owe it to.
    /// Tracked rather than derived from the current mode: the mode can
    /// change while the screen is dimmed, and the restore must survive it.
    @State private var loweredBrightness: LoweredBrightness?
    /// The adjust tray is up in place of the chevron.
#if DEBUG
    @State private var trayOpen = ScreenshotStage.shot == .liveTray
#else
    @State private var trayOpen = false
#endif
    /// The yellow square where the last tap or long press landed. A tap's
    /// is gone again after a moment; a long press's stays while the point
    /// is pinned. Either goes the instant the camera lets the point go.
    @State private var focusMark: FocusMark?
    @State private var pickingWhite = false

    private struct FocusMark: Equatable {
        let point: CGPoint
        let locked: Bool
        let id = UUID()
    }
    /// Which parameter the tray's dial drives.
    @State private var dialTarget: DialTarget = .exposure
    /// The lens row is showing a dial in place of its buttons.
    @State private var rowDial: RowDial?
    /// The dialled value when the finger went down; nil between drags.
    @State private var rowDialBase: Double?
    /// Restarts the row dial's fold-back timer on every touch.
    @State private var rowDialTouch = UUID()
    /// When the last drag across the lens row ended, so the lift that
    /// ends a zoom over a lens button isn't also a tap on it.
    @State private var rowDragEnded = Date.distantPast
    /// A passing line over the lens row (what a tap on green screen
    /// would have to be a hold to do).
    @State private var rowHint: String?

    private enum RowDial { case zoom, subject }
    /// Each back lens's magnification relative to Main, for the lens
    /// buttons' labels. Read once per stream: it walks the device list.
#if DEBUG
    @State private var lensFactors: [String: Double] = ScreenshotStage.lensFactors
#else
    @State private var lensFactors: [String: Double] = [:]
#endif
    @State private var nativeCrop: CGFloat?
    /// Stream health pill (fps · Mb/s · dropped). Persisted: someone who
    /// turns it on is debugging and wants it next stream too. The streamer
    /// reads the same key to decide whether to sample health at all.
    @AppStorage(StreamerDefaults.showHealth) private var showHealth = false
    /// Battery level for the dim readout and the low-battery tally.
    /// Monitoring runs only while this screen is up (see .task below).
    @ObservedObject private var battery = BatteryMonitor.shared
    @ObservedObject private var assistive = AssistiveTech.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor)
    private var differentiateWithoutColor

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
                onTapAtDevicePoint: { point, viewPoint in
                    touched()
                    let calibrating = pickingWhite && trayOpen
                        && activeTarget == .whiteBalance
                    pickingWhite = false
                    if calibrating {
                        streamer.calibrateWhiteBalance(at: point)
                        return
                    }
                    // Via the streamer so a tap keeps manual exposure locked.
                    streamer.focusAndExpose(at: point)
                    focusMark = FocusMark(point: viewPoint, locked: false)
                },
                onLongPressAtDevicePoint: { point, viewPoint in
                    touched()
                    streamer.lockFocusAndExposure(at: point)
                    focusMark = FocusMark(point: viewPoint, locked: true)
                },
                onPinchZoom: { phase, scale in
                    touched()
                    // Re-anchor at gesture start: zoom may have moved via
                    // the dial or a remote command since the last pinch,
                    // and a stale base makes the next pinch jump.
                    if phase == .began {
                        pinchBaseZoom = streamer.zoom
                    }
                    streamer.zoom = snappedZoom(min(
                        max(pinchBaseZoom * scale, 1),
                        streamer.camera.maxZoomFactor))
                },
                onVerticalDrag: { phase, travel in
                    verticalDrag(phase, travel: travel)
                }
            )
            .ignoresSafeArea()

#if DEBUG
            if let scene = ScreenshotStage.scene {
                Image(uiImage: scene)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
#endif

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
                    VStack(spacing: Theme.Space.l) {
                        lensRow
                        if trayOpen {
                            adjustTray
                        } else {
                            trayOpener
                        }
                    }
                }
            }
            .padding()
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2),
                       value: showsControls)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2),
                       value: trayOpen)

            // The focus marker, in the preview's own coordinate space (both
            // fill the screen). Not hit-testable: the next tap goes to the
            // picture, not the square.
            if let mark = focusMark {
                ZStack {
                    Color.clear
                    FocusIndicator(locked: mark.locked)
                        .position(mark.point)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .id(mark.id)
                .task(id: mark.id) {
                    guard !mark.locked else { return }
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard !Task.isCancelled, focusMark?.id == mark.id else { return }
                    withAnimation(.easeOut(duration: 0.3)) { focusMark = nil }
                }
            }

            // The drag's readout, centred where the eye already is. Only
            // while a finger is down: a value that lingers reads as a
            // control, and it isn't one.
            if dragBaseBias != nil {
                Text(readout(.exposure))
                    .font(.system(.body, design: .rounded).weight(.semibold)
                            .monospacedDigit())
                    .foregroundColor(Theme.cameraYellow)
                    .glassPill()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
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
                    .accessibilityElement()
                    .accessibilityLabel(L("Streaming — tap to wake"))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityInputLabels([L("Wake")])
                    .accessibilityAction { touched() }
            }

            // Above the dim overlay on purpose: a phone mounted out of
            // reach dims itself after ten seconds, and that is exactly
            // when knowing you're on air matters most.
            tallyBorder
            tallyBadge
        }
        .statusBar(hidden: true)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if streamer.idleAppearance != .standard && !idle &&
                    !assistive.suspendsIdle &&
                    Date().timeIntervalSince(lastInteraction)
                        > Self.idleAfterSeconds {
                    goIdle()
                }
            }
        }
        .onChange(of: assistive.suspendsIdle) { _ in touched() }
        // The preference is only reachable from the Setup screen today,
        // but a change arriving under a live idle view (an App Intent, a
        // future remote command) must not strand the screen dark or
        // control-less in a mode that no longer applies.
        .onChange(of: streamer.idleAppearance) { _ in wake() }
        .onChange(of: streamer.resolution) { _ in refreshNativeCrop() }
        .onChange(of: streamer.fps) { _ in refreshNativeCrop() }
        .onChange(of: streamer.activeColor) { _ in refreshNativeCrop() }
        // Battery monitoring is a device-wide flag, so it is held only
        // while this screen exists — the Setup screen has nothing to show.
        .onAppear {
            battery.retain()
            refreshLensFactors()
            // The camera let the tap point go (the scene changed): the
            // marker has nothing left to mark.
            streamer.camera.onTapPointReset = {
                Task { @MainActor in
                    withAnimation(.easeOut(duration: 0.3)) { focusMark = nil }
                }
            }
        }
        .onDisappear {
            battery.release()
            restoreBrightness()
            streamer.camera.onTapPointReset = nil
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
        if streamer.idleAppearance == .dim && loweredBrightness == nil {
            loweredBrightness = LoweredBrightness.lower(to: 0.05)
        }
        withAnimation(reduceMotion ? nil : .default) { idle = true }
    }

    /// Back to the controls.
    private func wake() {
        restoreBrightness()
        withAnimation(reduceMotion ? nil : .default) { idle = false }
        lastInteraction = Date()
    }

    /// Puts the brightness back exactly once, and only if we lowered it —
    /// writing a stale level over one the user (or iOS auto-brightness)
    /// has since changed is its own bug.
    private func restoreBrightness() {
        loweredBrightness?.restore()
        loweredBrightness = nil
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
                    .accessibilityHidden(true)
                Text("Streaming — tap to wake")
                    .font(.footnote)
                    .foregroundColor(.gray)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityInputLabels([L("Wake")])
                    .accessibilityAction { wake() }
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
            VStack(spacing: Theme.Space.xs) {
                HStack(spacing: Theme.Space.s) {
                    Image(systemName: batterySymbol(percent))
                        .font(.system(size: 44, weight: .regular))
                    Text(L("%lld%%", percent))
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
                if differentiateWithoutColor && battery.isLow {
                    Text(TallyStatus.lowBattery.displayName)
                        .font(.footnote.bold())
                        .foregroundColor(batteryTint)
                }
            }
        }
    }

    /// VoiceOver reads the level as a sentence; the glyph and the bolt are
    /// decoration once the percentage is spoken.
    private func batteryAccessibilityLabel(_ percent: Int) -> String {
        battery.isCharging
            ? L("Battery %lld percent, charging", percent)
            : L("Battery %lld percent", percent)
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

    @ViewBuilder private var tallyBadge: some View {
        if differentiateWithoutColor,
           let light = tallySettings.activeLight(for: activeTallyStatuses) {
            VStack {
                HStack {
                    Spacer()
                    Text(light.entry.status.displayName)
                        .font(.caption.bold())
                        .lineLimit(1)
                        .foregroundColor(Theme.textPrimary)
                        .glassPill()
                        .overlay(Capsule().strokeBorder(light.color, lineWidth: 2))
                }
                Spacer()
            }
            .padding()
            .padding(.top, Theme.controlButton + Theme.Space.s)
            .allowsHitTesting(false)
        }
    }

    /// Corner radius for the tally border. Modern iPhones have rounded
    /// display corners that physically clip a sharp-cornered stroke, so the
    /// border visibly broke at all four corners. There's no public API for
    /// the exact panel radius; a generous continuous curve covers every
    /// current device (their radii run ~40–55 pt) and errs by curving
    /// slightly *inside* the corner rather than getting cut off. Squared
    /// devices (SE, iPads) are detected by their zero bottom safe-area
    /// inset and keep square corners. Read per render, not cached: a
    /// value taken before the window existed, or before an iPad window
    /// was resized, would keep drawing the wrong corners.
    private var tallyCornerRadius: CGFloat {
        ActiveScreen.keyWindowSafeAreaInsets.bottom > 0 ? 58 : 0
    }

    private func tallyEdge(_ colour: Color, width: CGFloat,
                           pulse: Bool) -> some View {
        TallyEdge(colour: colour, width: width, pulse: pulse,
                  cornerRadius: tallyCornerRadius)
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
                ControlButton(streamer.isPaused ? L("Resume") : L("Pause"),
                              systemImage: streamer.isPaused
                                ? "play.fill" : "pause.fill",
                              highlighted: streamer.isPaused) {
                    touched()
                    streamer.setPaused(!streamer.isPaused, reason: .user)
                }
            }

            ControlButton(L("Stop camera"), systemImage: "stop.fill",
                          destructive: true, inputLabels: [L("Stop")]) {
                streamer.stop()
            }
        }
        .foregroundColor(Theme.textPrimary)
    }

    /// The status pill is also a menu: Stats on or off, and — in Clean
    /// feed or Dim screen — the idle view now, instead of waiting out
    /// the fuse. The small chevron is what says it opens.
    private var statusMenu: some View {
        Menu {
            Toggle(isOn: Binding(get: { showHealth },
                                 set: { on in
                                     touched()
                                     showHealth = on
                                 })) {
                Label("Stats", systemImage: "gauge")
            }
            if streamer.idleAppearance != .standard {
                Button {
                    goIdle()
                } label: {
                    Label(streamer.idleAppearance == .clean
                            ? L("Clean feed now") : L("Dim screen now"),
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
                    .secondaryOnGlass()
            }
            .foregroundColor(Theme.textPrimary)
            .glassPill()
        }
        .accessibilityLabel(streamer.status.displayName)
        .accessibilityInputLabels([streamer.status.displayName, L("Status")])
        .accessibilityShowsLargeContentViewer {
            Text(streamer.status.displayName)
        }
    }

    /// One row under the status bar for whatever needs saying. Today
    /// that is the lip-sync readout; nothing is drawn when there is
    /// nothing to say, and never two pills stacked.
    @ViewBuilder private var noticeRow: some View {
        if syncLabel != nil {
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
            return (L("Measuring sync"), Theme.accent)
        case .locked:
            return (L("Sync locked"), Theme.liveGreen)
        case .relocking:
            return (L("Recalibrating"), Theme.connectAmber)
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
                .secondaryOnGlass()
            }
            .disabled(streamer.syncState != .locked)
            .accessibilityLabel(syncAccessibilityLabel)
            .accessibilityHint(syncAccessibilityHint)
            .accessibilityInputLabels(syncInputLabels)
            .accessibilityShowsLargeContentViewer()
            Spacer()
        }
        .padding(.top, Theme.Space.s)
    }

    private var syncAccessibilityLabel: String {
        syncLabel?.text ?? ""
    }

    private var syncAccessibilityHint: String {
        streamer.syncState == .locked ? L("Recalibrate") : ""
    }

    private var syncInputLabels: [String] {
        guard let sync = syncLabel else { return [] }
        return streamer.syncState == .locked ? [sync.text, L("Recalibrate")]
                                             : [sync.text]
    }

    /// One-line health readout under the status bar: encoder output rate,
    /// wire bitrate, and frames dropped by backpressure this stream. All
    /// values come from counters the client keeps anyway (docs/ROADMAP.md
    /// "stream health overlay"); monospaced so they don't jitter.
    private func healthPill(_ health: Streamer.StreamHealth) -> some View {
        HStack {
            Text(L("%1$lld fps · %2$.1f Mb/s · %3$lld dropped",
                   health.fps, health.megabitsPerSecond, health.droppedFrames))
                .font(.caption.monospacedDigit())
                .glassPill()
                .accessibilityShowsLargeContentViewer()
            Spacer()
        }
        .padding(.top, Theme.Space.s)
        .foregroundColor(Theme.textPrimary)
    }

    // MARK: - Glance layer

    /// The chevron that opens the tray, under the lens row.
    private var trayOpener: some View {
        Button {
            touched()
            trayOpen = true
        } label: {
            Image(systemName: "chevron.up")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
                .frame(width: 56, height: 30)
                .glassBackground(Capsule(), style: .chip)
        }
        .accessibilityLabel("Adjust camera")
        .accessibilityInputLabels([L("Adjust camera"), L("Adjust")])
        .accessibilityShowsLargeContentViewer {
            Label(L("Adjust camera"), systemImage: "chevron.up")
        }
    }

    // MARK: - Lens row

    /// Points of finger travel per e-fold of zoom, and per metre of
    /// subject cutoff.
    private static let zoomDialPoints: CGFloat = 120
    private static let subjectDialPoints: Double = 60
    /// The Subject dial's stop past 5 m, which means no cutoff.
    private static let subjectAllStop = 5.5

    /// The lens buttons and the green screen button, above the tray
    /// whether it is open or not. Tapping the active lens brings up a
    /// zoom dial under the row, the buttons riding above it so the live
    /// zoom shows and the other lenses are a tap away; tapping the lit green screen button brings
    /// up the Subject cutoff dial instead. Sliding sideways across the
    /// dial or the row then drives it, and it tucks away shortly after
    /// the last touch.
    private var lensRow: some View {
        VStack(spacing: Theme.Space.s) {
            if let rowHint {
                Text(rowHint)
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundColor(Theme.textPrimary)
                    .glassPill()
                    .transition(.opacity)
                    .task(id: rowHint) {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        guard !Task.isCancelled else { return }
                        withAnimation { self.rowHint = nil }
                    }
            }
            VStack(spacing: Theme.Space.s) {
                if rowDial == .subject {
                    Text(subjectDistanceText)
                        .font(.system(.subheadline, design: .rounded).weight(.bold)
                                .monospacedDigit())
                        .foregroundColor(Theme.cameraYellow)
                        .glassPill()
                        .accessibilityHidden(true)
                }
                // Each dial keeps only its own buttons: the lenses for
                // zoom, green screen for Subject.
                HStack(spacing: Theme.Space.s) {
                    if rowDial != .subject {
                        lensButtons
                    }
                    if rowDial != .zoom, streamer.greenScreenOffered {
                        greenScreenButton
                            .padding(.leading, rowDial == nil ? Theme.Space.s : 0)
                    }
                }
                if let dial = rowDial {
                    DialRuler(ticks: dial == .zoom ? zoomTicks : subjectTicks)
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(DragGesture(minimumDistance: 12)
                .onChanged { value in
                    guard let dial = rowDial else { return }
                    touched()
                    if rowDialBase == nil {
                        rowDialBase = dial == .zoom
                            ? Double(streamer.zoom) : subjectDialValue
                    }
                    dragRowDial(by: value.translation.width)
                }
                .onEnded { _ in
                    guard rowDialBase != nil else { return }
                    rowDialBase = nil
                    rowDragEnded = Date()
                    rowDialTouch = UUID()
                })
            .task(id: rowDialTouch) {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled, rowDialBase == nil else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                    rowDial = nil
                }
            }
        }
    }

    private func dragRowDial(by travel: CGFloat) {
        guard let base = rowDialBase else { return }
        switch rowDial {
        case .zoom?:
            let zoom = min(max(CGFloat(base) * exp(-travel / Self.zoomDialPoints), 1),
                           streamer.camera.maxZoomFactor)
            let before = displayZoom
            streamer.zoom = snappedZoom(zoom)
            if floor(before) != floor(displayZoom) {
                Self.notchFeedback.selectionChanged()
            }
        case .subject?:
            let value = min(max(base - Double(travel) / Self.subjectDialPoints, 0.5),
                            Self.subjectAllStop)
            setSubjectDial((value * 10).rounded() / 10)
        case nil:
            break
        }
    }

    /// Sets the cutoff from a dial position, where anything past 5 m is
    /// All, with a click on each whole metre and on All.
    private func setSubjectDial(_ value: Double) {
        let next = value > 5 ? 0 : value
        guard next != streamer.greenScreenMaxDistance else { return }
        if floor(subjectDialValue) != floor(value) || next == 0 {
            Self.notchFeedback.selectionChanged()
        }
        streamer.greenScreenMaxDistance = next
    }

    /// The selected lens's magnification as the lens buttons show it.
    private var displayZoom: Double {
        (lensFactors[streamer.selectedLens.id] ?? 1) * Double(streamer.zoom)
    }

    private var zoomTicks: [(offset: CGFloat, label: String?)] {
        let factor = lensFactors[streamer.selectedLens.id] ?? 1
        let low = log(factor), high = log(factor * Double(streamer.camera.maxZoomFactor))
        let now = log(displayZoom)
        let place = { (v: Double) in CGFloat(v - now) * Self.zoomDialPoints }
        var ticks: [(offset: CGFloat, label: String?)] = stride(
            from: low, through: high, by: 0.1).map { (offset: place($0), label: nil) }
        let marks: [Double] = [0.5, 1, 2, 3, 5, 10, 15, 20, 25]
        for mark in marks where log(mark) >= low - 0.01 && log(mark) <= high + 0.01 {
            ticks.append((offset: place(log(mark)), label: Self.compactFactor(mark)))
        }
        return ticks
    }

    /// Where the Subject dial sits: the cutoff, the All stop, or (on
    /// Auto) where Auto has put it.
    private var subjectDialValue: Double {
        let distance = streamer.greenScreenMaxDistance
        if distance > 0 { return distance }
        if distance == 0 { return Self.subjectAllStop }
        return streamer.greenScreenAutoCutoff > 0 ? streamer.greenScreenAutoCutoff : 2
    }

    private var subjectTicks: [(offset: CGFloat, label: String?)] {
        let now = subjectDialValue
        let place = { (v: Double) in CGFloat((v - now) * Self.subjectDialPoints) }
        var ticks: [(offset: CGFloat, label: String?)] = stride(
            from: 0.5, through: 5, by: 0.25).map { (offset: place($0), label: nil) }
        let marks: [Double] = [0.5, 1, 2, 3, 4, 5]
        for mark in marks {
            ticks.append((offset: place(mark), label: Self.compactFactor(mark)))
        }
        ticks.append((offset: place(Self.subjectAllStop), label: L("All")))
        return ticks
    }

    private var subjectReadout: String {
        guard streamer.greenScreenMaxDistance < 0,
              streamer.greenScreenAutoCutoff > 0 else { return subjectDistanceText }
        return L("Auto") + ", " + subjectDistanceText
    }

    /// The Subject dial's readout: the A badge on the button already says Auto.
    private var subjectDistanceText: String {
        let distance = streamer.greenScreenMaxDistance
        if distance > 0 { return L("%.1f m", distance) }
        if distance == 0 { return L("All") }
        let cutoff = streamer.greenScreenAutoCutoff
        return cutoff > 0 ? L("%.1f m", cutoff) : L("Auto")
    }

    /// Green screen on the Live screen: lit while it is on, and only a
    /// hold switches it, since a switch restarts the camera and a stray
    /// tap mid-stream must not. A tap opens the Subject dial when depth
    /// is running (and, while it is open, hands the cutoff back to Auto,
    /// as tapping a selected chip does); otherwise it says to hold. The
    /// A badge says the cutoff is on Auto.
    private var greenScreenButton: some View {
        let on = streamer.greenScreenEnabled
        let depth = streamer.greenScreenDepthActive
        let auto = depth && streamer.greenScreenMaxDistance < 0
        let toggle = {
            touched()
            rowDial = nil
            streamer.greenScreenEnabled.toggle()
        }
        let tap = {
            touched()
            guard depth else {
                withAnimation {
                    rowHint = on ? L("Green screen is on, but without depth here, so there's no Subject dial. Hold to turn it off.")
                                 : L("Hold to turn on green screen")
                }
                return
            }
            if rowDial == .subject {
                streamer.greenScreenMaxDistance = Streamer.autoSubjectDistance
            } else {
                withAnimation { rowHint = L("Green screen shows in OBS, not in this preview") }
            }
            rowDial = .subject
            rowDialTouch = UUID()
        }
        return Image(systemName: "person.fill.viewfinder")
            .font(.system(size: 14, weight: .semibold))
            .onGlassText(on ? .black : Theme.textPrimary.opacity(0.85),
                         increased: on ? .black : Theme.textPrimary)
            .frame(width: 32, height: 32)
            .glassBackground(Circle(), style: on ? .solid(Theme.cameraYellow)
                                                 : .scrim(0.45))
            .overlay(alignment: .topTrailing) {
                if auto { autoBadge(selected: true) }
            }
            .contentShape(Circle())
            .onTapGesture(perform: tap)
            .onLongPressGesture(minimumDuration: 0.5, perform: toggle)
            .accessibilityElement()
            .accessibilityLabel(L("Green screen"))
            .accessibilityValue(on ? (depth ? L("Subject") + ", " + subjectReadout : L("On")) : L("Off"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: Text(on ? L("Turn off green screen")
                                                : L("Turn on green screen")),
                                 toggle)
            .adjustable(depth ? adjustSubject : nil)
            .accessibilityShowsLargeContentViewer {
                Label(L("Green screen"), systemImage: "person.fill.viewfinder")
            }
    }

    /// VoiceOver's stand-in for the Subject dial: half a metre a step,
    /// All past 5 m.
    private func adjustSubject(_ direction: AccessibilityAdjustmentDirection) {
        touched()
        let value = subjectDialValue
        setSubjectDial(direction == .increment
            ? min(value + 0.5, Self.subjectAllStop) : max(value - 0.5, 0.5))
    }

    /// The selected side's lenses in magnification order (.5 · 1× · 2),
    /// the Camera app's order, rather than the device list's Main-first
    /// order.
    private var sideLenses: [CameraManager.Lens] {
        streamer.availableLenses
            .filter { $0.position == streamer.selectedLens.position }
            .sorted { (lensFactors[$0.id] ?? 1) < (lensFactors[$1.id] ?? 1) }
    }

    private func refreshLensFactors() {
        var factors: [String: Double] = [:]
        for lens in streamer.availableLenses {
            factors[lens.id] = CameraManager.zoomFactorRelativeToMain(lens)
        }
        lensFactors = factors
        refreshNativeCrop()
    }

    private func refreshNativeCrop() {
        nativeCrop = CameraManager.nativeCropZoomFactor(
            resolution: streamer.resolution, fps: Int32(streamer.fps),
            color: streamer.activeColor)
    }

    private func snappedZoom(_ zoom: CGFloat) -> CGFloat {
        guard let crop = nativeCrop, streamer.selectedLens == mainLens,
              abs(zoom - crop) < 0.08 else { return zoom }
        return crop
    }

    private var mainLens: CameraManager.Lens? {
        streamer.availableLenses.first {
            $0.position == .back && $0.deviceType == .builtInWideAngleCamera
        }
    }

    private var onNativeCrop: Bool {
        guard let crop = nativeCrop else { return false }
        return streamer.selectedLens == mainLens && streamer.zoom == crop
    }

    /// The Camera app's lens row: one round button per back lens, the
    /// active one larger and yellow with the live zoom on it, so ".5 · 1× ·
    /// 2" reads exactly as it does in the app everyone already knows.
    /// Tapping switches the physical lens; pinching still zooms within it.
    /// Tapping the active lens brings up the zoom dial, and tapping it
    /// again returns the lens to its own zoom.
    private var lensButtons: some View {
        HStack(spacing: Theme.Space.s) {
            ForEach(sideLenses) { lens in
                let selected = lens == streamer.selectedLens
                let active = selected && !(lens == mainLens && onNativeCrop)
                lensChip(lensButtonLabel(lens, active: active),
                         active: active,
                         accessibilityLabel: lens.displayLabel,
                         accessibilityValue: lensAccessibilityValue(lens, active: active),
                         accessibilityHint: lensAccessibilityHint(active: selected),
                         adjust: selected ? adjustZoom : nil) {
                    if selected {
                        // First tap brings up the zoom dial, a second
                        // resets the zoom, like the green screen button.
                        // VoiceOver adjusts instead, so it resets at once.
                        if rowDial == .zoom || UIAccessibility.isVoiceOverRunning {
                            if streamer.zoom != 1 { streamer.zoom = 1 }
                        } else {
                            rowDial = .zoom
                        }
                        rowDialTouch = UUID()
                    } else {
                        streamer.selectedLens = lens
                    }
                }
                if lens == mainLens, let crop = nativeCrop {
                    let label = Self.compactFactor(Double(crop))
                    lensChip(onNativeCrop ? label + "×" : label,
                             active: onNativeCrop,
                             accessibilityLabel: lens.displayLabel,
                             accessibilityValue: label + "×",
                             accessibilityHint: "") {
                        if !selected { streamer.selectedLens = lens }
                        streamer.zoom = crop
                    }
                }
            }
        }
    }

    /// VoiceOver's stand-in for sliding across the lens row.
    private func adjustZoom(_ direction: AccessibilityAdjustmentDirection) {
        touched()
        let step: CGFloat = direction == .increment ? 1.25 : 0.8
        streamer.zoom = snappedZoom(min(max(streamer.zoom * step, 1),
                                        streamer.camera.maxZoomFactor))
    }

    private func lensChip(_ label: String, active: Bool,
                          accessibilityLabel: String,
                          accessibilityValue: String,
                          accessibilityHint: String,
                          adjust: ((AccessibilityAdjustmentDirection) -> Void)? = nil,
                          action: @escaping () -> Void) -> some View {
        Button {
            guard rowDialBase == nil,
                  Date().timeIntervalSince(rowDragEnded) > 0.3 else { return }
            touched()
            action()
        } label: {
            Text(label)
                .font(.system(size: active ? 13 : 11, weight: .bold,
                              design: .rounded).monospacedDigit())
                .onGlassText(active ? Theme.cameraYellow
                                    : Theme.textPrimary.opacity(0.85),
                             increased: active ? Theme.cameraYellow
                                               : Theme.textPrimary)
                .frame(width: active ? 38 : 32,
                       height: active ? 38 : 32)
                .glassBackground(Circle(),
                                 style: .scrim(active ? 0.6 : 0.45))
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(active ? .isSelected : [])
        .adjustable(adjust)
        .accessibilityShowsLargeContentViewer {
            Text(label)
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

    private func lensAccessibilityHint(active: Bool) -> String {
        guard active, streamer.zoom != 1 else { return "" }
        return L("Resets the zoom")
    }

    private func lensAccessibilityValue(_ lens: CameraManager.Lens,
                                        active: Bool) -> String {
        active ? lensButtonLabel(lens, active: true) : ""
    }

    /// Two significant figures, no trailing zeros: 1, 0.5, 2.4, 12.
    private static func compactFactor(_ value: Double) -> String {
        String(format: "%.2g", value)
    }

    // MARK: - Adjust tray

    /// What the dial can drive. The chip row shows the ones this camera
    /// has: ISO and Shutter need manual exposure, WB needs a lockable
    /// white balance. `exposure` is the EV chip, the auto-exposure bias.
    /// Zoom and Subject live on the lens row instead.
    private enum DialTarget: Hashable {
        case exposure, iso, shutter, whiteBalance, focus
    }

    private var dialTargets: [DialTarget] {
        var targets: [DialTarget] = [.focus]
        if streamer.camera.supportsWhiteBalanceLock { targets.append(.whiteBalance) }
        targets.append(.exposure)
        if streamer.camera.supportsManualExposure {
            targets.append(contentsOf: [.iso, .shutter])
        }
        return targets
    }

    /// The chosen target, or Exposure if what was chosen has since gone
    /// away (a camera without manual exposure or a WB lock).
    private var activeTarget: DialTarget {
        dialTargets.contains(dialTarget) ? dialTarget : .exposure
    }

    /// One dial, several parameters. The chips say which; a yellow A on a
    /// chip means that parameter is on auto, dragging the dial takes it
    /// manual, and tapping the active chip again hands it back to auto.
    /// EV is the auto-exposure bias, so it has no auto of its own; in
    /// manual exposure it sits idle. The buttons hold fixed places so
    /// none moves between chips: the chip's own tool (or a gap), Lock,
    /// Flashlight, Flip, Close.
    private var adjustTray: some View {
        VStack(spacing: Theme.Space.m) {
            chipRow
            dial
            HStack(spacing: Theme.Space.s) {
                // The one hint worth its space: the calibration is waiting
                // on a tap in the picture, which nothing else says.
                if pickingWhite && activeTarget == .whiteBalance {
                    Text(L("Tap the white paper in the picture"))
                        .font(.caption)
                        .secondaryOnGlass()
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Theme.Space.s)
                chipTool
                lockButton
                // Dimmed rather than removed on a camera without one, so
                // Flip and Close stay put when the camera flips.
                ControlButton(L("Flashlight"),
                              systemImage: streamer.flashlightOn
                                ? "bolt.fill" : "bolt.slash",
                              isOn: streamer.flashlightOn,
                              inputLabels: [L("Torch"), L("Light")]) {
                    touched()
                    streamer.flashlightOn.toggle()
                }
                .disabled(!streamer.camera.hasFlashlight)
                .opacity(streamer.camera.hasFlashlight ? 1 : 0.4)
                ControlButton(L("Flip camera"),
                              systemImage: "arrow.triangle.2.circlepath.camera",
                              inputLabels: [L("Switch camera"), L("Flip")]) {
                    touched()
                    streamer.flipCamera()
                }
                ControlButton(L("Close"), systemImage: "chevron.down",
                              inputLabels: [L("Done")]) {
                    touched()
                    trayOpen = false
                }
            }
        }
        .tint(Theme.cameraYellow)
        .glassPanel()
        .foregroundColor(Theme.textPrimary)
    }

    /// The selected chip's own button, or a gap the same size.
    @ViewBuilder private var chipTool: some View {
        switch activeTarget {
        case .shutter:
            ControlButton(L("Natural motion blur"),
                          systemImage: "camera.aperture",
                          isOn: streamer.naturalBlur,
                          inputLabels: [L("180 degree rule")]) {
                touched()
                streamer.naturalBlur.toggle()
            }
        case .whiteBalance:
            ControlButton(L("Calibrate white balance"),
                          systemImage: "eyedropper",
                          isOn: pickingWhite,
                          inputLabels: [L("Calibrate")]) {
                touched()
                pickingWhite.toggle()
            }
        default:
            Color.clear
                .frame(width: Theme.controlButton, height: Theme.controlButton)
                .accessibilityHidden(true)
        }
    }

    /// Tap locks or unlocks the selected value at what auto is doing
    /// now; hold does every value at once.
    private var lockButton: some View {
        let target = lockTarget(activeTarget)
        let all = streamer.allLocked
        let locked = streamer.isLocked(target)
        return ControlButton(L("Lock"),
                             systemImage: all ? "lock.rectangle.stack.fill"
                                : locked ? "lock.fill" : "lock.open",
                             isOn: locked,
                             inputLabels: [L("Unlock")],
                             longPress: (name: all ? L("Unlock all") : L("Lock all"),
                                         action: {
                                             touched()
                                             streamer.setAllLocked(!streamer.allLocked)
                                         })) {
            touched()
            streamer.setLocked(target, !streamer.isLocked(target))
        }
    }

    private func lockTarget(_ target: DialTarget) -> Streamer.LockTarget {
        switch target {
        case .exposure, .iso, .shutter: return .exposure
        case .whiteBalance: return .whiteBalance
        case .focus: return .focus
        }
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
            if selected, auto != true {
                setAuto(target)
            } else {
                dialTarget = target
            }
        } label: {
            Text(chipLabel(target))
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .onGlassText(selected ? .black : Theme.textPrimary.opacity(0.8),
                             increased: selected ? .black : Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .glassBackground(Capsule(),
                                 style: selected ? .solid(.white) : .chip)
                .overlay(alignment: .topTrailing) {
                    if auto == true { autoBadge(selected: selected) }
                }
        }
        .accessibilityLabel(chipAccessibilityLabel(target, auto: auto))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityInputLabels([chipLabel(target)])
        .accessibilityShowsLargeContentViewer {
            Text(chipLabel(target))
        }
    }

    /// The yellow A on anything that is on auto.
    private func autoBadge(selected: Bool) -> some View {
        Text("A")
            .font(.system(size: 8, weight: .heavy))
            .foregroundColor(selected ? Theme.cameraYellow : .black)
            .frame(width: 13, height: 13)
            .background(selected ? Color.black : Theme.cameraYellow, in: Circle())
            .offset(x: 2, y: -5)
    }

    private func chipAccessibilityLabel(_ target: DialTarget, auto: Bool?) -> String {
        let name = target == .exposure ? L("Exposure") : chipLabel(target)
        switch auto {
        case nil: return name
        case true?: return L("%@, auto", name)
        case false?: return L("%@, manual", name)
        }
    }

    private func chipLabel(_ target: DialTarget) -> String {
        switch target {
        case .exposure: return "EV"
        case .iso: return "ISO"
        case .shutter: return L("Shutter")
        case .whiteBalance: return L("WB")
        case .focus: return L("Focus")
        }
    }

    /// nil where the parameter has no auto (EV).
    private func isAuto(_ target: DialTarget) -> Bool? {
        switch target {
        case .exposure: return nil
        case .iso, .shutter: return streamer.exposureSetting == .auto
        case .whiteBalance: return streamer.whiteBalanceSetting == .auto
        case .focus: return streamer.focusSetting == .auto
        }
    }

    private func setAuto(_ target: DialTarget) {
        switch target {
        case .exposure:
            if streamer.exposureSetting == .auto { streamer.exposureBias = 0 }
        case .iso, .shutter: streamer.exposureSetting = .auto
        case .whiteBalance: streamer.whiteBalanceSetting = .auto
        case .focus: streamer.focusSetting = .auto
        }
    }

    /// A drag on the dial means "I want this by hand": the first touch
    /// locks the parameter at what auto was doing, so the picture doesn't
    /// jump before the finger moves. The bias has no manual to enter.
    private func engageManual(_ target: DialTarget) {
        if target != .exposure {
            streamer.setLocked(lockTarget(target), true)
        }
    }

    /// The dial: readout above, slider below, both in the camera yellow.
    /// A native slider rather than a drawn ruler — it tracks the finger
    /// with no lag (docs/UI_DESIGN.md §7) and VoiceOver already knows it.
    private var dial: some View {
        VStack(spacing: Theme.Space.xs) {
            Text(readout(activeTarget))
                .font(.system(.subheadline, design: .rounded).weight(.bold)
                        .monospacedDigit())
                .foregroundColor(Theme.cameraYellow)
                .accessibilityHidden(true)
            dialSlider(activeTarget)
                .accessibilityLabel(chipLabel(activeTarget))
                .accessibilityValue(readout(activeTarget))
        }
    }

    @ViewBuilder private func dialSlider(_ target: DialTarget) -> some View {
        switch target {
        case .exposure:
            notchedSlider(exposureStops, value: doubleBinding($streamer.exposureBias),
                          target: target)
                .disabled(streamer.exposureSetting == .manual)
        case .iso:
            notchedSlider(isoStops, value: doubleBinding($streamer.iso),
                          logScale: true, target: target)
        case .shutter:
            notchedSlider(shutterStops, value: $streamer.shutterSeconds,
                          logScale: true, target: target)
        case .whiteBalance:
            VStack(spacing: 0) {
                slider(floatBinding($streamer.whiteBalanceTemperature),
                       in: 2500...8000, target: target)
                lightSources
            }
        case .focus:
            slider(floatBinding($streamer.lensPosition), in: 0...1,
                   target: target)
        }
    }

    @ViewBuilder
    private func slider<V>(_ value: Binding<V>, in range: ClosedRange<V>,
                           step: V.Stride? = nil,
                           target: DialTarget) -> some View
        where V: BinaryFloatingPoint, V.Stride: BinaryFloatingPoint {
        let bound = Binding(get: { value.wrappedValue },
                            set: { newValue in
                                if assistive.suspendsIdle {
                                    engageManual(target)
                                }
                                value.wrappedValue = newValue
                            })
        let editingChanged: (Bool) -> Void = { editing in
            if editing {
                touched()
                engageManual(target)
            }
        }
        if let step {
            Slider(value: bound, in: range, step: step,
                   onEditingChanged: editingChanged)
        } else {
            Slider(value: bound, in: range, onEditingChanged: editingChanged)
        }
    }

    private static let notchFeedback = UISelectionFeedbackGenerator()

    /// A dial that clicks between fixed stops (camera-style thirds for
    /// EV and ISO, the usual shutter speeds), with a tick
    /// under the track for each and a haptic click as the thumb crosses
    /// one. The slider runs over stop indices, so log-spaced stops sit
    /// evenly.
    private func notchedSlider(_ stops: [Double], value: Binding<Double>,
                               logScale: Bool = false,
                               target: DialTarget) -> some View {
        let distance: (Double, Double) -> Double = logScale
            ? { abs(log($0 / $1)) } : { abs($0 - $1) }
        let nearest: () -> Int = {
            let v = value.wrappedValue
            return stops.indices.min {
                distance(stops[$0], v) < distance(stops[$1], v)
            } ?? 0
        }
        let index = Binding<Double>(
            get: { Double(nearest()) },
            set: { position in
                let i = min(max(Int(position.rounded()), 0), stops.count - 1)
                guard i != nearest() else { return }
                Self.notchFeedback.selectionChanged()
                value.wrappedValue = stops[i]
            })
        return VStack(spacing: 2) {
            slider(index, in: 0...Double(max(stops.count - 1, 1)), step: 1,
                   target: target)
            GeometryReader { geo in
                // The thumb's centre travels 14 pt in from each end.
                let span = geo.size.width - 28
                ForEach(stops.indices, id: \.self) { i in
                    Capsule()
                        .fill(Theme.textPrimary.opacity(0.4))
                        .frame(width: 1.5, height: 6)
                        .position(x: 14 + span * CGFloat(i)
                                    / CGFloat(max(stops.count - 1, 1)),
                                  y: 3)
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
        }
    }

    /// Where common light sources sit on the WB dial (2500–8000 K), so
    /// the number means something at a glance.
    private var lightSources: some View {
        let sources: [(kelvin: CGFloat, symbol: String)] = [
            // light.panel is iOS 16+; iOS 15 shows the filled bulb.
            (2800, "lightbulb"),
            (4000, UIImage(systemName: "light.panel") != nil
                ? "light.panel" : "lightbulb.fill"),
            (5500, "sun.max"), (6500, "cloud"), (7500, "building.2"),
        ]
        return GeometryReader { geo in
            let span = geo.size.width - 28
            ForEach(sources, id: \.kelvin) { source in
                Image(systemName: source.symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.textPrimary.opacity(0.6))
                    .position(x: 14 + span * (source.kelvin - 2500) / 5500, y: 8)
            }
        }
        .frame(height: 16)
        .accessibilityHidden(true)
    }

    /// Third stops, within what the bias range allows.
    private var exposureStops: [Double] {
        let r = streamer.camera.exposureBiasRange
        let lo = (Double(r.lowerBound) * 3).rounded(.up)
        let hi = (Double(r.upperBound) * 3).rounded(.down)
        return lo < hi ? Array(stride(from: lo, through: hi, by: 1)).map { $0 / 3 } : [0]
    }

    /// Third stops, within the camera's ISO range.
    private var isoStops: [Double] {
        let r = streamer.camera.isoRange
        let all: [Double] = [25, 32, 40, 50, 64, 80, 100, 125, 160, 200, 250, 320,
                             400, 500, 640, 800, 1000, 1250, 1600, 2000, 2500,
                             3200, 4000, 5000, 6400, 8000, 10000, 12800, 16000,
                             20000, 25600]
        let low = Double(r.lowerBound), high = Double(r.upperBound)
        let stops = all.filter { $0 >= low && $0 <= high }
        return stops.count > 1 ? stops : [Double(r.lowerBound), Double(r.upperBound)]
    }

    /// The usual shutter speeds, slow on the left, plus the flicker-safe
    /// 1/50, 1/100 and 1/120 and the 180° picks 1/48 and 1/120; within
    /// what the format and the frame interval allow.
    private var shutterStops: [Double] {
        let minSeconds = max(streamer.camera.minShutterSeconds, 1.0 / 8000)
        let maxSeconds = streamer.camera.maxShutterSeconds(fps: Int32(streamer.fps))
        let denominators: [Double] = [1, 2, 3, 4, 5, 6, 8, 10, 13, 15, 20, 24, 25,
                                      30, 40, 48, 50, 60, 80, 100, 120, 125, 160,
                                      200, 250, 320, 400, 500, 640, 800, 1000,
                                      1250, 1600, 2000, 2500, 3200, 4000, 5000,
                                      6400, 8000]
        let low = minSeconds * 0.999, high = maxSeconds * 1.001
        let stops = denominators.map { 1 / $0 }.filter { $0 >= low && $0 <= high }
        return stops.count > 1 ? stops : [maxSeconds, minSeconds]
    }

    private func readout(_ target: DialTarget) -> String {
        switch target {
        case .exposure:
            return String(format: "%+.1f EV", streamer.exposureBias)
        case .iso:
            return streamer.exposureSetting == .manual
                ? "ISO \(Int(streamer.iso.rounded()))" : L("Auto")
        case .shutter:
            return streamer.exposureSetting == .manual ? shutterReadout : L("Auto")
        case .whiteBalance:
            return streamer.whiteBalanceSetting == .locked
                ? "\(Int(streamer.whiteBalanceTemperature)) K" : L("Auto")
        case .focus:
            return streamer.focusSetting == .locked
                ? String(format: "%.2f", streamer.lensPosition) : L("Auto")
        }
    }

    private var shutterReadout: String {
        let seconds = streamer.shutterSeconds
        guard seconds < 1 else { return String(format: "%.0fs", seconds) }
        return "1/\(Int((1 / seconds).rounded()))"
    }

    private func doubleBinding(_ source: Binding<Float>) -> Binding<Double> {
        Binding(get: { Double(source.wrappedValue) },
                set: { source.wrappedValue = Float($0) })
    }

    /// Bridges a Float model value to the CGFloat sliders.
    private func floatBinding(_ source: Binding<Float>) -> Binding<CGFloat> {
        Binding(get: { CGFloat(source.wrappedValue) },
                set: { source.wrappedValue = Float($0) })
    }
}

/// The lens row's dial: ticks that slide under a fixed yellow centre
/// line, the value under the line being the current one.
private struct DialRuler: View {
    /// Points from the centre line, with a label on the major ticks.
    let ticks: [(offset: CGFloat, label: String?)]

    var body: some View {
        Canvas { context, size in
            let mid = size.width / 2
            for tick in ticks {
                let x = mid + tick.offset
                guard x > 4, x < size.width - 4 else { continue }
                let height: CGFloat = tick.label == nil ? 8 : 14
                context.fill(Path(CGRect(x: x - 0.75, y: size.height - 8 - height,
                                         width: 1.5, height: height)),
                             with: .color(Theme.textPrimary
                                .opacity(tick.label == nil ? 0.4 : 0.75)))
                if let label = tick.label {
                    context.draw(Text(label)
                                    .font(.system(size: 10, weight: .bold,
                                                  design: .rounded))
                                    .foregroundColor(Theme.textPrimary.opacity(0.62)),
                                 at: CGPoint(x: x, y: size.height - 8 - height - 9))
                }
            }
            context.fill(Path(roundedRect: CGRect(x: mid - 1, y: 6, width: 2,
                                                  height: size.height - 12),
                              cornerRadius: 1),
                         with: .color(Theme.cameraYellow))
        }
        .frame(height: 54)
        .glassBackground(RoundedRectangle(cornerRadius: 14, style: .continuous),
                         style: .scrim(0.5))
    }
}

private extension View {
    @ViewBuilder func adjustable(
        _ action: ((AccessibilityAdjustmentDirection) -> Void)?) -> some View {
        if let action {
            accessibilityAdjustableAction(action)
        } else {
            self
        }
    }
}

/// The Camera app's focus square: a thin yellow rounded rectangle that
/// lands with a small scale-in, plus an "AE/AF Lock" tag under it for a
/// pinned point. Drawn where the finger was; the parent decides when it
/// goes.
private struct FocusIndicator: View {
    let locked: Bool
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Theme.Space.s) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Theme.cameraYellow, lineWidth: 1.5)
                .frame(width: 72, height: 72)
            if locked {
                Text("AE/AF Lock")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, Theme.Space.s)
                    .padding(.vertical, Theme.Space.xs)
                    .background(Theme.cameraYellow, in: Capsule())
            }
        }
        .scaleEffect(appeared || reduceMotion ? 1 : 1.3)
        .opacity(appeared ? 1 : 0.4)
        .onAppear {
            withAnimation(.easeOut(duration: 0.15)) { appeared = true }
        }
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
