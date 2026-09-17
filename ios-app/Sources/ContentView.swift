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

    // The behaviour toggles live in a sheet (OptionsView) so the main
    // screen stays short — see that file for why. The explanations live
    // in a second sheet (DocumentationView) so the sections themselves
    // are pure controls. Format (resolution · frame rate · codec) is a
    // third sheet behind one row, the Camera app's own pattern.
    @State private var showOptions = false
    @State private var showDocs = false
    @State private var showFormat = false

    // Standby keeps the phone awake (see Streamer.updateIdleTimer) so
    // remote start stays reachable; this dim overlay is what makes that
    // affordable — same pattern as StreamingView's, on a longer fuse
    // because this screen is also where settings get changed.
    @State private var dimmed = false
    @State private var lastInteraction = Date()
    @State private var previousBrightness: CGFloat = UIScreen.main.brightness

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
            .sheet(isPresented: $showDocs) {
                NavigationView {
                    DocumentationView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showDocs = false }
                            }
                        }
                }
                .navigationViewStyle(.stack)
                .tint(Theme.accent)
            }
            .sheet(isPresented: $showFormat) {
                FormatSheet(availableResolutions: availableResolutions,
                            availableFrameRates: availableFrameRates)
                    .environmentObject(streamer)
            }
            // Opening or closing a sheet is activity too.
            .onChange(of: showOptions) { _ in lastInteraction = Date() }
            .onChange(of: showDocs) { _ in lastInteraction = Date() }
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
        .onChange(of: streamer.highFrameRate) { _ in refreshCapabilities() }
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
                if streamer.standbyActive
                    && streamer.idleAppearance == .dim &&
                    !showOptions && !showDocs && !showFormat && !dimmed &&
                    Date().timeIntervalSince(lastInteraction) > Self.dimAfterSeconds {
                    dim()
                } else if !streamer.standbyActive && dimmed {
                    // Standby ended underneath the overlay (remote start
                    // fired, toggle turned off, port lost) — wake up.
                    undim()
                }
            }
        }
        .onDisappear {
            if dimmed {
                UIScreen.main.brightness = previousBrightness
                dimmed = false
            }
        }
    }

    private func dim() {
        previousBrightness = UIScreen.main.brightness
        UIScreen.main.brightness = 0.05
        withAnimation { dimmed = true }
    }

    private func undim() {
        UIScreen.main.brightness = previousBrightness
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
                Text("Ready for remote start — tap to wake")
                    .font(.footnote)
                    .foregroundColor(.gray)
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
            Text("LensLink")
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
            HStack(spacing: Theme.Space.m) {
                Image(systemName: computerSymbol)
                    .font(.system(size: 26, weight: .regular))
                    .foregroundColor(streamer.status.tint)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(connectionTitle)
                        .font(.headline)
                        .lineLimit(1)
                    HStack(spacing: Theme.Space.xs + 2) {
                        Circle()
                            .fill(streamer.status.tint)
                            .frame(width: 8, height: 8)
                        Text(connectionSubtitle)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: Theme.Space.s)
                if streamer.status == .standby {
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
                        .textSelection(.enabled)
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
                        Text("Enter \(Text(ip).bold()) as the source's Phone IP (same Wi-Fi) — or plug in USB and set Connection to \"USB cable\" (Windows needs iTunes).")
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

    /// A laptop glyph over USB, a desktop otherwise: the transport is
    /// the one thing about the computer the phone can actually see.
    private var computerSymbol: String {
        streamer.obsTransport == "usb" ? "laptopcomputer" : "desktopcomputer"
    }

    private var connectionTitle: String {
        streamer.obsHost ?? "OBS Studio"
    }

    /// Status word first (docs/UI_DESIGN.md §2), then what the plugin
    /// said about itself: version and transport, only while it is here
    /// to say it.
    private var connectionSubtitle: String {
        var parts = [streamer.status.displayName]
        if streamer.status != .idle, !streamer.isStreaming {
            if let version = streamer.obsVersion {
                parts.append("OBS \(version)")
            }
            switch streamer.obsTransport {
            case "usb": parts.append("USB")
            case "lan": parts.append("Wi-Fi")
            default: break
            }
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Camera

    private var cameraSection: some View {
        Section {
            Picker(selection: $streamer.selectedLens) {
                ForEach(streamer.availableLenses) { lens in
                    Text(lens.label).tag(lens)
                }
            } label: {
                SettingsRowLabel("Camera", systemImage: "camera.fill",
                                 color: Theme.connectAmber)
            }

            // One row for resolution · frame rate · codec, with the
            // pickers behind it: three rows of pickers said the same
            // thing three times.
            Button {
                showFormat = true
            } label: {
                HStack {
                    SettingsRowLabel("Format", systemImage: "rectangle.stack",
                                     color: Theme.accent)
                    Spacer()
                    Text(formatSummary)
                        .foregroundColor(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle(isOn: $streamer.greenScreenEnabled) {
                SettingsRowLabel("Green screen",
                                 systemImage: "person.fill.viewfinder",
                                 color: Theme.liveGreen)
            }

            if streamer.cameraPermissionDenied || streamer.micPermissionDenied {
                Button("Camera access denied — open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
    }

    /// "4K · 60 fps · HEVC", plus "· HDR" or "· Log" when the colour
    /// isn't Standard — the format row's value.
    private var formatSummary: String {
        var parts = [streamer.resolution.rawValue, "\(streamer.fps) fps",
                     streamer.codec.label]
        switch streamer.colorSetting {
        case .sdr: break
        case .hlg: parts.append("HDR")
        case .log: parts.append("Log")
        }
        if streamer.quality == .maximum { parts.append("Max") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Start

    @State private var extensionStatus = ""

    /// The two things this screen exists to start, stacked: the camera
    /// (accent) and the screen broadcast (the quieter fill). The
    /// broadcast button's face is ours; the (invisible) system broadcast
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
                ActionRowLabel(title: "Start Camera",
                               systemImage: "video.fill",
                               style: .primary)
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            ZStack {
                ActionRowLabel(title: "Mirror Screen",
                               systemImage: "rectangle.on.rectangle",
                               style: .secondary)
                BroadcastPickerOverlay()
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
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
                SettingsRowLabel("Send phone mic to OBS", systemImage: "mic.fill",
                                 color: Theme.connectAmber)
            }
            if streamer.sendMicAudio {
                Picker("Microphone", selection: $streamer.selectedMicID) {
                    ForEach(streamer.micOptions) { mic in
                        Text(mic.name).tag(mic.id)
                    }
                }
            }
            Toggle(isOn: $streamer.sendAudioReference) {
                SettingsRowLabel("Auto lip-sync reference",
                                 systemImage: "waveform",
                                 color: Theme.accent)
            }
        }
    }

    // MARK: - Tail (Options / About)

    /// Rows that close the form: the Options sheet (remote start, dim,
    /// effects, tally, diagnostics — each explained in the Documentation
    /// sheet, not in a footer here), the Documentation sheet, and the
    /// links. TestFlight testers otherwise have no pointer to the
    /// plugin/docs/issues; the version line gives bug reports a build to
    /// cite.
    private var tailSection: some View {
        Section {
            Button {
                showOptions = true
            } label: {
                disclosureRow("Options", systemImage: "gearshape.fill",
                              color: Theme.idleGrey)
            }
            .buttonStyle(.plain)
            Button {
                showDocs = true
            } label: {
                disclosureRow("Documentation", systemImage: "book.fill",
                              color: Theme.accent)
            }
            .buttonStyle(.plain)
            Link(destination: Self.reportProblemURL) {
                SettingsRowLabel("Report a problem", systemImage: "ladybug.fill",
                                 color: Theme.errorRed)
            }
            Link(destination: URL(string: "https://github.com/MyNamesEMurray/LensLink")!) {
                SettingsRowLabel("LensLink on GitHub", systemImage: "link",
                                 color: Theme.idleGrey)
            }
        } footer: {
            // The one surviving footer: bug reports need a build to cite,
            // and the version has no control it could live beside.
            Text(Self.versionLine)
        }
    }

    private func disclosureRow(_ title: String, systemImage: String,
                               color: Color) -> some View {
        HStack {
            SettingsRowLabel(title, systemImage: systemImage, color: color)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
    }

    /// The GitHub bug-report form with the phone-side facts prefilled
    /// through the form's field ids (template query parameters) — testers
    /// shouldn't have to transcribe build numbers and device names.
    private static let reportProblemURL: URL = {
        var sys = utsname()
        uname(&sys)
        let model = withUnsafePointer(to: &sys.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "unknown"
            }
        }
        var url = URLComponents(
            string: "https://github.com/MyNamesEMurray/LensLink/issues/new")!
        var items = [
            URLQueryItem(name: "template", value: "bug-report.yml"),
            URLQueryItem(name: "versions", value:
                "\(versionLine), \(model), iOS \(UIDevice.current.systemVersion)"),
        ]
        // TestFlight builds carry a sandbox receipt; prefill the install
        // dropdown so reports say which distribution they came from.
        if Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" {
            items.append(URLQueryItem(name: "install", value: "TestFlight"))
        }
        url.queryItems = items
        return url.url!
    }()

    private static let versionLine: String = {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "LensLink v\(version) (\(build))"
    }()
}

/// The Settings app's row anatomy: a coloured rounded tile with a white
/// symbol, then the title. Shared by the Setup screen and Options so the
/// two read as one list style (docs/UI_DESIGN.md §6.1).
struct SettingsRowLabel: View {
    let title: String
    let systemImage: String
    let color: Color

    init(_ title: String, systemImage: String, color: Color) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 29, height: 29)
                .background(color, in: RoundedRectangle(cornerRadius: 7,
                                                        style: .continuous))
        }
    }
}

/// Resolution · frame rate · codec · color behind the Format row. The
/// lists are the Setup screen's cached capability filters, passed in so
/// this sheet never runs a format scan of its own.
///
/// Codec and Color are drawn as check rows rather than pickers because
/// the two constrain each other — HDR and Apple Log are HEVC only, green
/// screen is Standard only — and a picker that silently hides H.264
/// reads as a bug ("where did H.264 go?"). Every choice stays visible,
/// and a choice that will change another setting says so in its
/// subtitle before you tap it. The model enforces the same rules
/// (Streamer's codec/colorSetting didSets), so the row is a preview of
/// what will happen, not a second implementation of it.
private struct FormatSheet: View {
    @EnvironmentObject private var streamer: Streamer
    @Environment(\.dismiss) private var dismiss
    let availableResolutions: [CameraManager.Resolution]
    let availableFrameRates: [Int]

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Picker("Resolution", selection: $streamer.resolution) {
                        ForEach(availableResolutions) { resolution in
                            Text(resolution.rawValue).tag(resolution)
                        }
                    }
                    Picker("Frame rate", selection: $streamer.fps) {
                        ForEach(availableFrameRates, id: \.self) { fps in
                            Text("\(fps) fps").tag(fps)
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
                    ChoiceRow(title: VideoCodec.h264.label,
                              detail: streamer.colorSetting == .sdr
                                ? nil
                                : "Switches Color to Standard — HDR and Apple Log are HEVC only",
                              selected: streamer.codec == .h264) {
                        streamer.codec = .h264
                    }
                } header: {
                    Text("Codec")
                }

                Section {
                    ChoiceRow(title: "Balanced",
                              detail: "Safe on ordinary Wi-Fi",
                              selected: streamer.quality == .balanced) {
                        streamer.quality = .balanced
                    }
                    ChoiceRow(title: "Maximum",
                              detail: "Finds the most your connection carries — more data, more heat; best over USB",
                              selected: streamer.quality == .maximum) {
                        streamer.quality = .maximum
                    }
                } header: {
                    Text("Quality")
                }

                // Hidden on devices that can't encode Main10 — a choice
                // that can never work is worse than none (only
                // "Standard" would remain). Apple Log appears only when
                // some lens actually has a Log capture format (iOS 17+).
                if VideoEncoder.hdrSupported {
                    Section {
                        ChoiceRow(title: "Standard", detail: nil,
                                  selected: streamer.colorSetting == .sdr) {
                            streamer.colorSetting = .sdr
                        }
                        ChoiceRow(title: "HDR (HLG)",
                                  detail: nonStandardColorDetail,
                                  selected: streamer.colorSetting == .hlg) {
                            streamer.colorSetting = .hlg
                        }
                        if CameraManager.appleLogCaptureAvailable {
                            ChoiceRow(title: "Apple Log",
                                      detail: nonStandardColorDetail,
                                      selected: streamer.colorSetting == .log) {
                                streamer.colorSetting = .log
                            }
                        }
                    } header: {
                        Text("Color")
                    }
                }
            }
            .navigationTitle("Format")
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

    /// What picking HDR or Apple Log will change, said before the tap:
    /// the codec if it is H.264, green screen if it is on, and the
    /// standing constraint otherwise.
    private var nonStandardColorDetail: String? {
        var notes: [String] = []
        if streamer.codec == .h264 {
            notes.append("Switches Codec to HEVC")
        }
        if streamer.greenScreenEnabled {
            notes.append("Turns Green screen off")
        }
        return notes.isEmpty ? "HEVC only" : notes.joined(separator: " · ")
    }
}

/// One selectable row with a checkmark: a title, an optional subtitle
/// naming a consequence, and the accent check on the chosen one — the
/// Settings app's own pattern for a short list of exclusive choices.
private struct ChoiceRow: View {
    let title: String
    let detail: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundColor(.primary)
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
