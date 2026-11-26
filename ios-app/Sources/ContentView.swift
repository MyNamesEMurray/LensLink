import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var streamer: Streamer

    // Cached per change, not per render: a Form body re-evaluates on any
    // published change, and these hit AVCaptureDevice discovery/format
    // scans (capability checks) or getifaddrs (the IP) each time.
    @State private var wifiIP: String?
    @State private var availableResolutions: [CameraManager.Resolution] = []
    @State private var availableFrameRates: [Int] = []

    // Collapsible extras: essential exactly once, then noise. Persisted so
    // the form stays compact after the user has read them.
    @AppStorage("showConnectionHelp") private var showConnectionHelp = true

    // Two sheets keep the main screen short: Camera (everything that
    // shapes the picture, behind one summary row) and Settings
    // (OptionsView: how the app behaves, plus Help and Documentation).
#if DEBUG
    @State private var showOptions = ScreenshotStage.shot == .options
    @State private var showFormat = ScreenshotStage.shot == .format
#else
    @State private var showOptions = false
    @State private var showFormat = false
#endif

    // Armed standby keeps the phone awake (see Streamer.updateIdleTimer)
    // so remote start stays reachable; this dim overlay is what makes that
    // affordable — same pattern as StreamingView's, on a longer fuse
    // because this screen is also where settings get changed.
    @State private var dimmed = false
    @State private var lastInteraction = Date()
    @State private var loweredBrightness: LoweredBrightness?
    @ObservedObject private var assistive = AssistiveTech.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let dimAfterSeconds: TimeInterval = 60

    var body: some View {
        if streamer.isStreaming {
            StreamingView()
        } else {
            settingsForm
        }
    }

    // The form is the per-stream decisions in order — the computer,
    // the camera, the microphone — then the two Start buttons and a
    // tail of Options / Documentation / links. A large title, not a
    // navigation bar: nothing is ever pushed, so nothing needs a back
    // button (docs/UI_DESIGN.md §6.1).
    private var settingsForm: some View {
        ZStack {
            Form {
                titleHeader
                connectionSection
                cameraSection
                startSection
                micSection
                tailSection
            }
            .tint(Theme.accent)
            // Every touch is activity — scrolling and reading included.
            // Before this, only streamer-visible changes reset the standby
            // dim's fuse, so a minute spent in a menu that doesn't touch
            // the streamer (the tally screen, say) read as "idle" and the
            // screen dimmed mid-use. A passive UIKit sensor, NOT a SwiftUI
            // DragGesture(minimumDistance: 0): that gesture competed for
            // every first touch, breaking single-tap on the menu pickers
            // (on some iOS releases) and on the broadcast picker overlay
            // (everywhere) — #96, #97, #99.
            .background(TouchActivitySensor { lastInteraction = Date() })
            .sheet(isPresented: $showOptions) {
                OptionsView()
                    .environmentObject(streamer)
            }
            .sheet(isPresented: $showFormat) {
                FormatSheet(availableResolutions: availableResolutions,
                            availableFrameRates: availableFrameRates)
                    .environmentObject(streamer)
            }
            // Opening or closing a sheet is activity too.
            .onChange(of: showOptions) { _ in lastInteraction = Date() }
            .onChange(of: showFormat) { _ in lastInteraction = Date() }

            if dimmed {
                dimOverlay
            }
        }
        .onAppear {
            wifiIP = NetworkInfo.wifiIPAddress()
            refreshCapabilities()
            lastInteraction = Date()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.willEnterForegroundNotification)) { _ in
            wifiIP = NetworkInfo.wifiIPAddress()
        }
        .onChange(of: streamer.selectedLens) { _ in refreshCapabilities() }
        .onChange(of: streamer.resolution) { _ in
            streamer.clampCaptureSettings()
            refreshCapabilities()
        }
        // Any settings change or connection event counts as activity;
        // scrolling alone doesn't, which the long fuse absorbs.
        .onReceive(streamer.objectWillChange) { _ in
            if !dimmed {
                lastInteraction = Date()
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                // Gated on the idle view being Dim screen — Clean feed
                // has nothing to mean on a settings form, so only the
                // dimming choice reaches this screen — and on no sheet
                // being up: the overlay would sit behind the sheet with
                // its tap-to-wake unreachable, leaving the screen dark
                // with no visible way back.
                if streamer.awaitingRemoteStart
                    && streamer.idleAppearance == .dim &&
                    !assistive.suspendsIdle &&
                    !showOptions && !showFormat && !dimmed &&
                    Date().timeIntervalSince(lastInteraction) > Self.dimAfterSeconds {
                    dim()
                } else if !streamer.awaitingRemoteStart && dimmed {
                    // Armed standby ended underneath the overlay (remote
                    // start fired, disarmed, port lost) — wake up.
                    undim()
                }
            }
        }
        .onChange(of: assistive.suspendsIdle) { on in
            if on && dimmed {
                undim()
            } else {
                lastInteraction = Date()
            }
        }
        .onDisappear {
            if dimmed {
                loweredBrightness?.restore()
                loweredBrightness = nil
                dimmed = false
            }
        }
    }

    private func dim() {
        loweredBrightness = LoweredBrightness.lower(to: 0.05)
        withAnimation { dimmed = true }
    }

    private func undim() {
        loweredBrightness?.restore()
        loweredBrightness = nil
        withAnimation { dimmed = false }
        lastInteraction = Date()
    }

    /// Near-black tap-to-wake overlay (StreamingView's, in standby amber):
    /// the phone stays awake so OBS can start the camera, without the
    /// screen-on battery cost.
    private var dimOverlay: some View {
        ZStack {
            Color.black.opacity(0.96).ignoresSafeArea()
            VStack(spacing: 8) {
                Image(systemName: "video.fill")
                    .foregroundColor(Theme.connectAmber.opacity(0.6))
                    .accessibilityHidden(true)
                Text("Ready for remote start — tap to wake")
                    .font(.footnote)
                    .foregroundColor(.gray)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityInputLabels([L("Wake")])
                    .accessibilityAction { undim() }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { undim() }
    }

    private func refreshCapabilities() {
        availableResolutions = CameraManager.Resolution.allCases.filter {
            CameraManager.supports(resolution: $0, fps: 30,
                                   lens: streamer.selectedLens)
        }
        availableFrameRates = streamer.candidateFrameRates.filter {
            CameraManager.supports(resolution: streamer.resolution,
                                   fps: Int32($0),
                                   lens: streamer.selectedLens)
        }
    }

    // MARK: - Title

    /// The app's name as a plain large title, the way the system's own
    /// apps open. The wordmark asset stays in the catalog for the icon
    /// and the site; on the screen a word is enough.
    private var titleHeader: some View {
        Section {
            Text(verbatim: "LensLink")
                .font(.largeTitle.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: Theme.Space.s, leading: Theme.Space.xl,
                                          bottom: 0, trailing: Theme.Space.xl))
        }
    }

    // MARK: - Connection

    /// The computer, as a card: its name once the plugin has said it
    /// (`identify`), the status dot and word, and on the right either
    /// Start (OBS is connected and can start the camera) or the phone's
    /// address (nothing is connected yet, and the address is how OBS
    /// finds this phone). Setup instructions collapse away once read.
    private var connectionSection: some View {
        Section {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        connectionSummary
                        connectionAction
                    }
                } else {
                    HStack(spacing: Theme.Space.m) {
                        connectionSummary
                            .layoutPriority(1)
                        Spacer(minLength: Theme.Space.s)
                        connectionAction
                    }
                }
            }
            .padding(.vertical, Theme.Space.xs)
            if streamer.discoverable == false {
                // The Bonjour advertise was denied: the phone won't show
                // up by name in OBS and nothing else says why. iOS's
                // per-app Settings page carries the Local Network toggle.
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Not visible by name in OBS — tap to allow Local Network in Settings. Connecting by IP still works.",
                          systemImage: "wifi.exclamationmark")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            DisclosureGroup("How to connect", isExpanded: $showConnectionHelp) {
                Label {
                    Text("Install the LensLink plugin in OBS (GitHub link below), then add a **LensLink Camera** or **LensLink Screen** source.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                } icon: {
                    Image(systemName: "1.circle")
                }
                Label {
                    if let ip = wifiIP {
                        Text(markdown: L("Enter **%@** as the source's Phone IP (same Wi-Fi) — or plug in USB and set Connection to \"USB cable\" (Windows needs iTunes).", ip))
                            .font(.callout)
                            .foregroundColor(.secondary)
                    } else {
                        Text("No Wi-Fi address — join Wi-Fi, or plug in USB and set the source's Connection to \"USB cable\" (Windows needs iTunes).")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: "2.circle")
                }
            }
        }
    }

    private var connectionSummary: some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: computerSymbol)
                .font(.system(size: 26, weight: .regular))
                .foregroundColor(streamer.status.tint)
                .frame(width: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(connectionTitle)
                    .font(.headline)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                HStack(spacing: Theme.Space.xs + 2) {
                    Circle()
                        .fill(streamer.status.tint)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text(streamer.status.displayName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                }
                if let details = connectionDetails {
                    Text(details)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                        .padding(.leading, 8 + Theme.Space.xs + 2)
                }
            }
        }
    }

    @ViewBuilder private var connectionAction: some View {
        if streamer.status == .standby || streamer.status == .unarmedStandby {
            Button {
                Task { await streamer.start() }
            } label: {
                Text("Start")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, Theme.Space.l)
                    .padding(.vertical, Theme.Space.s)
                    .background(Theme.accent, in: Capsule())
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
        } else if let ip = wifiIP {
            Text(ip)
                .font(.callout.monospacedDigit().bold())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .textSelection(.enabled)
        }
    }

    /// A laptop glyph over USB, a desktop otherwise: the transport is
    /// the one thing about the computer the phone can actually see.
    private var computerSymbol: String {
        streamer.obsTransport == "usb" ? "laptopcomputer" : "desktopcomputer"
    }

    private var connectionTitle: String {
        streamer.obsHost ?? "OBS Studio"
    }

    private var connectionDetails: String? {
        guard streamer.status != .idle, !streamer.isStreaming else { return nil }
        var parts: [String] = []
        if let version = streamer.obsVersion {
            parts.append("OBS \(version)")
        }
        switch streamer.obsTransport {
        case "usb": parts.append("USB")
        case "lan": parts.append("Wi-Fi")
        default: break
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Camera

    /// One row for every camera choice: the lens as its title, the
    /// format (and green screen) under it, the Camera sheet behind it.
    /// Choices that limit each other (depth and format, reframe and 4K)
    /// then sit on one screen.
    private var cameraSection: some View {
        Section {
            Button {
                showFormat = true
            } label: {
                HStack {
                    SettingsRowLabel(streamer.selectedLens.displayLabel,
                                     systemImage: "camera.fill",
                                     color: Theme.connectAmber,
                                     subtitle: cameraSummary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.secondary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if streamer.cameraPermissionDenied || streamer.micPermissionDenied {
                Button("Camera access denied — open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        } header: {
            Text("Camera")
        }
    }

    private var cameraSummary: String {
        streamer.greenScreenEnabled
            ? formatSummary + " · " + L("Green screen")
            : formatSummary
    }

    /// "4K · 60 fps · HEVC", plus "· HDR" or "· Log" when the colour
    /// isn't Standard — the format row's value.
    private var formatSummary: String {
        var parts = [streamer.resolution.rawValue, L("%lld fps", streamer.fps),
                     streamer.codec.label]
        switch streamer.colorSetting {
        case .sdr: break
        case .hlg: parts.append("HDR")
        case .log: parts.append(L("Log"))
        }
        if streamer.quality == .balanced { parts.append(L("Stable")) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Start

    @State private var extensionStatus = ""

    /// The things this screen exists to start, stacked: the camera
    /// (accent), remote start and the screen broadcast (the quieter
    /// fill). The broadcast button's face is ours; the (invisible) system broadcast
    /// picker stretched over it receives the tap, because iOS won't
    /// start a broadcast any other way.
    private var startSection: some View {
        Section {
            // Surface a broken extension unconditionally (sideloading can
            // silently drop it); the healthy state and the broadcast-link
            // probe live in Options → Diagnostics.
            if !extensionStatus.isEmpty && !extensionStatus.hasPrefix("✓") {
                Text(extensionStatus)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Button {
                Task { await streamer.start() }
            } label: {
                ActionRowLabel(title: L("Start Camera"),
                               systemImage: "video.fill",
                               style: .primary)
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Button {
                streamer.setRemoteStartArmed(!streamer.remoteStartArmed)
            } label: {
                ActionRowLabel(title: streamer.remoteStartArmed
                                   ? L("Disarm Remote Start")
                                   : L("Arm Remote Start"),
                               systemImage: streamer.remoteStartArmed
                                   ? "xmark.circle"
                                   : "dot.radiowaves.left.and.right",
                               style: .secondary)
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            ZStack {
                ActionRowLabel(title: L("Mirror Screen"),
                               systemImage: "rectangle.on.rectangle",
                               style: .secondary)
                    .accessibilityHidden(true)
                BroadcastPickerOverlay()
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        .onAppear {
            // Whether the extension survived sideloading — the broadcast
            // picker can show a stale entry even when it didn't.
            extensionStatus = BroadcastProbe.installedExtensionDescription()
        }
    }

    // MARK: - Microphone

    /// Mic role is a per-stream decision, not a set-and-forget behaviour
    /// toggle, so it earns main-screen space. Which mic is chosen here
    /// before Start rather than on the Live screen: a set-once decision,
    /// and the Live screen is for the shot. Still live if changed
    /// mid-stream from the web panel, which keeps its own mic row.
    private var micSection: some View {
        Section {
            Toggle(isOn: $streamer.sendMicAudio) {
                SettingsRowLabel(L("Send phone mic to OBS"), systemImage: "mic.fill",
                                 color: Theme.connectAmber)
            }
            if streamer.sendMicAudio {
                Picker("Microphone", selection: $streamer.selectedMicID) {
                    ForEach(streamer.micOptions) { mic in
                        Text(mic.displayName).tag(mic.id)
                    }
                }
            }
            Toggle(isOn: $streamer.sendAudioReference) {
                SettingsRowLabel(L("Auto lip-sync reference"),
                                 systemImage: "waveform",
                                 color: Theme.accent)
            }
        }
    }

    // MARK: - Tail

    /// The Settings sheet: how the app behaves, plus Help (documentation,
    /// diagnostics, bug report, the version line).
    private var tailSection: some View {
        Section {
            Button {
                showOptions = true
            } label: {
                HStack {
                    SettingsRowLabel(L("Settings"), systemImage: "gearshape.fill",
                                     color: Theme.idleGrey)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.secondary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// The Settings app's row anatomy: a coloured rounded tile with a white
/// symbol, then the title — and, for the Documentation index, a line of
/// secondary text under it. Shared by the Setup screen, Options and
/// Documentation so they read as one list style (docs/UI_DESIGN.md §6.1).
struct SettingsRowLabel: View {
    let title: String
    let systemImage: String
    let color: Color
    let subtitle: String?
    let info: LocalizedStringKey?

    init(_ title: String, systemImage: String, color: Color,
         subtitle: String? = nil, info: LocalizedStringKey? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
        self.subtitle = subtitle
        self.info = info
    }

    var body: some View {
        Label {
            HStack(spacing: Theme.Space.xs + 2) {
                if let subtitle = subtitle {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text(title)
                }
                if let info = info {
                    InfoButton(title: title, text: info)
                }
            }
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 29, height: 29)
                .background(color, in: RoundedRectangle(cornerRadius: 7,
                                                        style: .continuous))
                .accessibilityHidden(true)
        }
    }
}

/// The Camera sheet behind the Setup screen's camera row: every choice
/// that shapes the picture, top to bottom in the order they limit each
/// other — lens, format, green screen, picture processing. The lists
/// are the Setup screen's cached capability filters, passed in so this
/// sheet never runs a format scan of its own.
///
/// Codec and Color are drawn as check rows rather than pickers because
/// the two constrain each other — HDR and Apple Log are HEVC only, green
/// screen is Standard only — and a picker that silently hides H.264
/// reads as a bug ("where did H.264 go?"). Every choice stays visible;
/// the 10-bit colours carry a two-word "HEVC only" and nothing else,
/// and the model (Streamer's codec/colorSetting didSets) does the
/// switching when a choice needs it. Maximum wears a Beta tag.
private struct FormatSheet: View {
    @EnvironmentObject private var streamer: Streamer
    @Environment(\.dismiss) private var dismiss
    let availableResolutions: [CameraManager.Resolution]
    let availableFrameRates: [Int]

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Picker(selection: $streamer.selectedLens) {
                        ForEach(streamer.availableLenses) { lens in
                            Text(lens.displayLabel).tag(lens)
                        }
                    } label: {
                        SettingsRowLabel(L("Camera"), systemImage: "camera.fill",
                                         color: Theme.connectAmber)
                    }
                }

                Section {
                    formatMenu("Resolution", value: streamer.resolution.rawValue) {
                        Picker("Resolution", selection: $streamer.resolution) {
                            ForEach(availableResolutions) { resolution in
                                depthItem(resolution.rawValue,
                                          depth: resolutionDepth(resolution))
                                    .tag(resolution)
                            }
                        }
                    }
                    formatMenu("Frame rate", value: L("%lld fps", streamer.fps)) {
                        Picker("Frame rate", selection: $streamer.fps) {
                            ForEach(availableFrameRates, id: \.self) { fps in
                                depthItem(L("%lld fps", fps),
                                          depth: frameRateDepth(fps))
                                    .tag(fps)
                            }
                        }
                    }
                }

                Section {
                    if VideoEncoder.isSupported(.hevc) {
                        ChoiceRow(title: VideoCodec.hevc.label,
                                  detail: nil,
                                  selected: streamer.codec == .hevc) {
                            streamer.codec = .hevc
                        }
                    }
                    ChoiceRow(title: VideoCodec.h264.label, detail: nil,
                              selected: streamer.codec == .h264) {
                        streamer.codec = .h264
                    }
                } header: {
                    Text("Codec")
                }

                Section {
                    ChoiceRow(title: L("Stable"), detail: nil,
                              selected: streamer.quality == .balanced) {
                        streamer.quality = .balanced
                    }
                    ChoiceRow(title: L("Maximum"), detail: nil,
                              selected: streamer.quality == .maximum) {
                        streamer.quality = .maximum
                    }
                } header: {
                    HStack(spacing: Theme.Space.xs) {
                        Text("Bitrate")
                        InfoButton(title: L("Bitrate"), text: SettingInfo.bitrate)
                    }
                }

                // Hidden on devices that can't encode Main10 — a choice
                // that can never work is worse than none (only
                // "Standard" would remain). Apple Log appears only when
                // some lens actually has a Log capture format (iOS 17+).
                if VideoEncoder.hdrSupported {
                    Section {
                        ChoiceRow(title: L("Standard"), detail: nil,
                                  selected: streamer.colorSetting == .sdr) {
                            streamer.colorSetting = .sdr
                        }
                        ChoiceRow(title: L("HDR (HLG)"), detail: nil,
                                  selected: streamer.colorSetting == .hlg) {
                            streamer.colorSetting = .hlg
                        }
                        if CameraManager.appleLogCaptureAvailable {
                            ChoiceRow(title: L("Apple Log"), detail: nil,
                                      selected: streamer.colorSetting == .log) {
                                streamer.colorSetting = .log
                            }
                        }
                    } header: {
                        Text("Color")
                    }
                }

                Section {
                    Toggle(isOn: $streamer.greenScreenEnabled) {
                        SettingsRowLabel(L("Green screen"),
                                         systemImage: "person.fill.viewfinder",
                                         color: Theme.liveGreen,
                                         info: SettingInfo.greenScreen)
                    }
                }

                Section {
                    Picker(selection: $streamer.stabilization) {
                        ForEach(Streamer.Stabilization.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    } label: {
                        SettingsRowLabel(L("Stabilization"),
                                         systemImage: "waveform.path",
                                         color: Theme.cameraYellow,
                                         info: SettingInfo.stabilization)
                    }
                    if Streamer.reframeAvailable {
                        // Only the switch is disabled at 4K: a disabled
                        // row would take its ⓘ with it, and the ⓘ is
                        // what explains why it is off.
                        HStack {
                            SettingsRowLabel(L("High-quality reframe"),
                                             systemImage: "crop",
                                             color: Theme.cameraYellow,
                                             info: SettingInfo.reframe)
                            Spacer(minLength: 0)
                            Toggle(L("High-quality reframe"), isOn: $streamer.reframeHQ)
                                .labelsHidden()
                                .disabled(streamer.resolution == .uhd4k)
                        }
                    }
                    Toggle(isOn: $streamer.allowVideoEffects) {
                        SettingsRowLabel(L("Allow system video effects"),
                                         systemImage: "wand.and.stars",
                                         color: Theme.idleGrey,
                                         info: SettingInfo.videoEffects)
                    }
                    Toggle(isOn: $streamer.rememberCameraSettings) {
                        SettingsRowLabel(L("Remember camera settings"),
                                         systemImage: "clock.arrow.circlepath",
                                         color: Theme.connectAmber,
                                         info: SettingInfo.remember)
                    }
                } header: {
                    Text("Picture")
                }
            }
            .navigationTitle("Camera")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
        .tint(Theme.accent)
    }

    /// A picker row whose collapsed value is just the format, while its
    /// menu items carry the depth tags.
    private func formatMenu<Content: View>(_ title: LocalizedStringKey, value: String,
                                           @ViewBuilder content: () -> Content) -> some View {
        Menu(content: content) {
            HStack {
                Text(title).foregroundColor(.primary)
                Spacer()
                Text(value)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
            }
        }
    }

    /// A menu item with its depth tag: the layers icon and "Depth" when
    /// depth assist runs at it, or the frame rates that would have it.
    @ViewBuilder
    private func depthItem(_ title: String, depth: DepthTag) -> some View {
        switch depth {
        case .none:
            Text(title)
        case .here:
            Label {
                Text(title)
                Text(L("Depth"))
            } icon: {
                Image(systemName: "square.3.layers.3d")
            }
        case .at(let rates):
            Label {
                Text(title)
                Text(L("Depth at %@ fps", rates.map(String.init).joined(separator: ", ")))
            } icon: {
                EmptyView()
            }
        }
    }

    private enum DepthTag { case none, here, at([Int]) }

    private func resolutionDepth(_ resolution: CameraManager.Resolution) -> DepthTag {
        guard streamer.greenScreenEnabled else { return .none }
        let rates = availableFrameRates.filter {
            CameraManager.supportsDepth(resolution: resolution, fps: Int32($0),
                                        lens: streamer.selectedLens)
        }
        if rates.contains(streamer.fps) { return .here }
        return rates.isEmpty ? .none : .at(rates)
    }

    private func frameRateDepth(_ fps: Int) -> DepthTag {
        guard streamer.greenScreenEnabled,
              CameraManager.supportsDepth(resolution: streamer.resolution,
                                          fps: Int32(fps),
                                          lens: streamer.selectedLens) else {
            return .none
        }
        return .here
    }
}

/// One selectable row with a checkmark: a title, an optional short
/// subtitle, an optional small tag ("Beta"), and the accent check on the
/// chosen one — the Settings app's own pattern for a short list of
/// exclusive choices.
private struct ChoiceRow: View {
    let title: String
    let detail: String?
    var tag: String? = nil
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Theme.Space.s) {
                        Text(title)
                            .foregroundColor(.primary)
                        if let tag {
                            Text(tag)
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(Theme.accent)
                                .padding(.horizontal, Theme.Space.s)
                                .padding(.vertical, 2)
                                .background(Theme.accent.opacity(0.15),
                                            in: Capsule())
                        }
                    }
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundColor(Theme.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The one action-button face used by both Start buttons, so "Start
/// Camera" and "Mirror Screen" read as the same kind of control: the
/// camera in the accent, the broadcast in the system's quieter fill.
private struct ActionRowLabel: View {
    enum Style { case primary, secondary }

    let title: String
    let systemImage: String
    var style: Style = .primary

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.body.weight(.semibold))
            .foregroundColor(style == .primary ? .white : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(style == .primary
                            ? Theme.accent : Color(.secondarySystemFill),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
    }
}
