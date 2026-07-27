import SwiftUI
import AVFoundation

/// Full-screen live view shown while streaming: camera preview with
/// tap-to-focus and pinch-to-zoom, camera controls, and optional
/// battery-saving dimming.
struct StreamingView: View {
    @EnvironmentObject private var streamer: Streamer

    @State private var dimmed = false
    @State private var lastInteraction = Date()
    @State private var pinchBaseZoom: CGFloat = 1
    @State private var previousBrightness: CGFloat = UIScreen.main.brightness
    /// Stream health pill (fps · Mb/s · dropped). Persisted: someone who
    /// turns it on is debugging and wants it next stream too. The streamer
    /// reads the same key to decide whether to sample health at all.
    @AppStorage(StreamerDefaults.showHealth) private var showHealth = false

    private static let dimAfterSeconds: TimeInterval = 10

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
                    // the slider or a remote command since the last pinch,
                    // and a stale base makes the next pinch jump.
                    if phase == .began {
                        pinchBaseZoom = streamer.zoom
                    }
                    streamer.zoom = min(
                        max(pinchBaseZoom * scale, 1),
                        streamer.camera.maxZoomFactor)
                }
            )
            .ignoresSafeArea()

            VStack {
                statusBar
                // Its own row: sharing the top bar with three buttons
                // truncated the words ("Sync lo…"), and an unreadable
                // status is worse than none.
                if syncLabel != nil {
                    syncPill
                }
                if showHealth, let health = streamer.health {
                    healthPill(health)
                }
                Spacer()
                controlPanel
            }
            .padding()

            if dimmed {
                dimOverlay
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
                if streamer.dimWhileStreaming && !dimmed &&
                    Date().timeIntervalSince(lastInteraction) > Self.dimAfterSeconds {
                    dim()
                }
            }
        }
        .onDisappear {
            if dimmed {
                UIScreen.main.brightness = previousBrightness
            }
        }
    }

    private func touched() {
        lastInteraction = Date()
    }

    private func dim() {
        previousBrightness = UIScreen.main.brightness
        UIScreen.main.brightness = 0.05
        withAnimation { dimmed = true }
    }

    private func undim() {
        UIScreen.main.brightness = previousBrightness
        withAnimation { dimmed = false }
        touched()
    }

    private var dimOverlay: some View {
        ZStack {
            // Near-black overlay: real battery savings on OLED, and the
            // brightness drop covers LCDs.
            Color.black.opacity(0.96).ignoresSafeArea()
            VStack(spacing: 8) {
                Image(systemName: "video.fill")
                    .foregroundColor(.green.opacity(0.6))
                Text("Streaming — tap to wake")
                    .font(.footnote)
                    .foregroundColor(.gray)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { undim() }
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
        return active
    }

    @ViewBuilder private var tallyBorder: some View {
        if let light = tallySettings.activeLight(for: activeTallyStatuses) {
            // On air keeps the heaviest stroke; everything informational
            // stays lighter so live remains the most emphatic state even
            // in user-chosen colours.
            tallyEdge(light.color, width: light.status == .onAir ? 6 : 4)
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

    private func tallyEdge(_ colour: Color, width: CGFloat) -> some View {
        // allowsHitTesting(false): the border sits over the preview, and
        // tap-to-focus near the screen edge must still reach it.
        RoundedRectangle(cornerRadius: Self.tallyCornerRadius,
                         style: .continuous)
            .strokeBorder(colour, lineWidth: width)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.15), value: colour)
    }

    private var statusBar: some View {
        HStack(spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.s) {
                Circle()
                    .fill(streamer.status.tint)
                    .frame(width: 8, height: 8)
                Text(streamer.status.displayName)
                    .font(.footnote.bold())
                    .lineLimit(1)
            }
            .glassPill()

            Spacer()

            ControlButton(systemImage: "gauge", active: showHealth) {
                touched()
                showHealth.toggle()
            }

            ControlButton(systemImage: "moon.fill") {
                touched()
                dim()
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

    private var controlPanel: some View {
        VStack(spacing: Theme.Space.m) {
            sliderRow(minIcon: "minus.magnifyingglass",
                      maxIcon: "plus.magnifyingglass",
                      value: $streamer.zoom,
                      range: 1...max(streamer.camera.maxZoomFactor, 1.1),
                      readout: String(format: "%.1f×", streamer.zoom))

            exposureRows

            whiteBalanceRow

            greenScreenRow

            micRow

            HStack(spacing: Theme.Space.m) {
                Picker("Focus", selection: $streamer.focusSetting) {
                    Text("AF").tag(Streamer.FocusSetting.auto)
                    Text("Lock").tag(Streamer.FocusSetting.locked)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
                .onChange(of: streamer.focusSetting) { _ in touched() }

                if streamer.focusSetting == .locked {
                    Slider(value: floatBinding($streamer.lensPosition),
                           in: 0...1) { editing in
                        if editing { touched() }
                    }
                } else {
                    // AF mode: tap the preview to focus (a gesture, per
                    // UI_DESIGN.md §6.2). No inline label — it crowded the
                    // row and collapsed to one letter per line.
                    Spacer()
                }

                if streamer.camera.hasFlashlight {
                    ControlButton(systemImage: streamer.flashlightOn
                                    ? "bolt.fill" : "bolt.slash",
                                  active: streamer.flashlightOn) {
                        touched()
                        streamer.flashlightOn.toggle()
                    }
                }

                Menu {
                    ForEach(streamer.availableLenses) { lens in
                        Button {
                            touched()
                            streamer.selectedLens = lens
                        } label: {
                            if lens == streamer.selectedLens {
                                Label(lens.label, systemImage: "checkmark")
                            } else {
                                Text(lens.label)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "camera.aperture")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(Theme.textPrimary)
                        .frame(width: Theme.controlButton,
                               height: Theme.controlButton)
                        .background(Theme.glassChip, in: Circle())
                }

                ControlButton(
                    systemImage: "arrow.triangle.2.circlepath.camera") {
                    touched()
                    streamer.flipCamera()
                }
            }
        }
        .tint(Theme.accent)
        .glassPanel()
        .foregroundColor(Theme.textPrimary)
    }

    /// Exposure: the classic bias slider in AE, or ISO + shutter rows in
    /// Manual (only offered when the camera supports custom exposure). The
    /// AE/Manual segmented control shares the row with the bias slider.
    @ViewBuilder
    private var exposureRows: some View {
        if streamer.camera.supportsManualExposure {
            HStack(spacing: Theme.Space.m) {
                Picker("Exposure", selection: $streamer.exposureSetting) {
                    Text("AE").tag(Streamer.ExposureSetting.auto)
                    Text("Manual").tag(Streamer.ExposureSetting.manual)
                }
                .pickerStyle(.segmented)
                .frame(width: 130)
                .onChange(of: streamer.exposureSetting) { _ in touched() }

                if streamer.exposureSetting == .auto {
                    Slider(value: floatBinding($streamer.exposureBias),
                           in: exposureRange) { editing in
                        if editing { touched() }
                    }
                    Text(String(format: "%+.1f", streamer.exposureBias))
                        .font(.caption.monospacedDigit())
                        .frame(width: 44, alignment: .trailing)
                } else {
                    Spacer()
                }
            }
            if streamer.exposureSetting == .manual {
                sliderRow(minIcon: "dial.min",
                          maxIcon: "dial.max",
                          value: floatBinding($streamer.iso),
                          range: isoRange,
                          readout: "\(Int(streamer.iso))")
                HStack(spacing: Theme.Space.m) {
                    Image(systemName: "tortoise")
                    // Log scale: shutter steps are multiplicative (1/60 →
                    // 1/125 → 1/250…); a linear slider crams everything
                    // usable into its first pixels.
                    Slider(value: shutterBinding, in: 0...1) { editing in
                        if editing { touched() }
                    }
                    Image(systemName: "hare")
                    Text(shutterReadout)
                        .font(.caption.monospacedDigit())
                        .frame(width: 44, alignment: .trailing)
                }
            }
        } else {
            sliderRow(minIcon: "sun.min",
                      maxIcon: "sun.max",
                      value: floatBinding($streamer.exposureBias),
                      range: exposureRange,
                      readout: String(format: "%+.1f", streamer.exposureBias))
        }
    }

    /// White balance: AWB / Lock segmented + a colour-temperature slider
    /// while locked. Hidden entirely on cameras without WB gain locking.
    @ViewBuilder
    private var whiteBalanceRow: some View {
        if streamer.camera.supportsWhiteBalanceLock {
            HStack(spacing: Theme.Space.m) {
                Picker("White balance", selection: $streamer.whiteBalanceSetting) {
                    Text("AWB").tag(Streamer.WhiteBalanceSetting.auto)
                    Text("Lock").tag(Streamer.WhiteBalanceSetting.locked)
                }
                .pickerStyle(.segmented)
                .frame(width: 130)
                .onChange(of: streamer.whiteBalanceSetting) { _ in touched() }

                if streamer.whiteBalanceSetting == .locked {
                    Slider(value: floatBinding($streamer.whiteBalanceTemperature),
                           in: 2500...8000) { editing in
                        if editing { touched() }
                    }
                    Text("\(Int(streamer.whiteBalanceTemperature))K")
                        .font(.caption.monospacedDigit())
                        .frame(width: 44, alignment: .trailing)
                } else {
                    Spacer()
                }
            }
        }
    }

    /// Green screen subject distance (docs/UI_DESIGN.md §5): anything
    /// farther than this is background even where the person shape
    /// disagrees. Shown only while the stream is composited *with*
    /// depth assist running — without depth the cutoff can do nothing,
    /// and screen mirror never shows this screen at all. Standard
    /// slider-row anatomy (§4); the readout doubles as the "All"
    /// affordance: it shows the cutoff and taps back to no-cutoff
    /// (model value 0), while "All" itself is plain text.
    @ViewBuilder
    private var greenScreenRow: some View {
        if streamer.greenScreenDepthActive {
            HStack(spacing: Theme.Space.m) {
                Image(systemName: "person.fill.viewfinder")
                Slider(value: subjectDistanceBinding,
                       in: 0.5...5.0, step: 0.1) { editing in
                    if editing { touched() }
                }
                Image(systemName: "person.2.fill")
                if streamer.greenScreenMaxDistance > 0 {
                    Button {
                        touched()
                        streamer.greenScreenMaxDistance = 0
                    } label: {
                        Text(String(format: "%.1f m",
                                    streamer.greenScreenMaxDistance))
                            .font(.caption.monospacedDigit())
                            .frame(width: 44, alignment: .trailing)
                    }
                } else {
                    Text("All")
                        .font(.caption.monospacedDigit())
                        .frame(width: 44, alignment: .trailing)
                }
            }
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

    /// Mic picker: which microphone feeds OBS. Shown only while the phone
    /// mic is being sent as the source's audio (Options → Send phone mic);
    /// switching is live — the tap re-installs on the new input.
    @ViewBuilder
    private var micRow: some View {
        if streamer.sendMicAudio {
            HStack(spacing: Theme.Space.m) {
                Image(systemName: "mic.fill")
                Menu {
                    ForEach(streamer.micOptions) { mic in
                        Button {
                            touched()
                            streamer.selectedMicID = mic.id
                        } label: {
                            if mic.id == streamer.selectedMicID {
                                Label(mic.name, systemImage: "checkmark")
                            } else {
                                Text(mic.name)
                            }
                        }
                    }
                } label: {
                    Text(selectedMicName)
                        .font(.subheadline)
                        .foregroundColor(Theme.textPrimary)
                        .padding(.horizontal, Theme.Space.m)
                        .frame(height: Theme.controlButton)
                        .background(Theme.glassChip, in: Capsule())
                }
                Spacer()
            }
        }
    }

    private var selectedMicName: String {
        streamer.micOptions
            .first { $0.id == streamer.selectedMicID }?.name ?? "Auto"
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

    /// Shared zoom/exposure slider row: leading icon · slider · trailing
    /// icon · monospaced readout (docs/UI_DESIGN.md §4).
    private func sliderRow(minIcon: String, maxIcon: String,
                           value: Binding<CGFloat>,
                           range: ClosedRange<CGFloat>,
                           readout: String) -> some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: minIcon)
            Slider(value: value, in: range) { editing in
                if editing { touched() }
            }
            Image(systemName: maxIcon)
            Text(readout)
                .font(.caption.monospacedDigit())
                .frame(width: 44, alignment: .trailing)
        }
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
