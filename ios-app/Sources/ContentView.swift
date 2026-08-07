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
    // are pure controls.
    @State private var showOptions = false
    @State private var showDocs = false

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

    // The form is the per-stream decisions in order — Connect,
    // Camera & color, Microphone, Screen mirror — the stream modules
    // saying which OBS source they talk to and ending in the same
    // full-width action button, plus a two-row tail (Options sheet +
    // GitHub/version). The banner is the title (no NavigationView: nothing
    // is ever pushed, and the wordmark replaces the large-title text).
    private var settingsForm: some View {
        ZStack {
            Form {
                bannerHeader
                connectSection
                cameraSection
                micSection
                screenMirrorSection
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
            // Opening or closing a sheet is activity too.
            .onChange(of: showOptions) { _ in lastInteraction = Date() }
            .onChange(of: showDocs) { _ in lastInteraction = Date() }

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
                // Gated on the dim setting (one switch governs both dims)
                // and on no sheet being up: the overlay would sit behind
                // the sheet with its tap-to-wake unreachable, leaving the
                // screen dark with no visible way back.
                if streamer.standbyActive && streamer.dimWhileStreaming &&
                    !showOptions && !showDocs && !dimmed &&
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
        availableFrameRates = [30, 60].filter {
            CameraManager.supports(resolution: streamer.resolution,
                                   fps: Int32($0),
                                   lens: streamer.selectedLens)
        }
    }

    // MARK: - Banner

    /// The wordmark as the screen's title. Light/dark variants switch
    /// automatically via the asset catalog's luminosity appearances.
    private var bannerHeader: some View {
        Section {
            Image("Banner")
                .resizable()
                .scaledToFit()
                .frame(height: 48)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("LensLink")
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .padding(.top, Theme.Space.s)
        }
    }

    // MARK: - Connect

    /// Status + the phone's address on one line; setup instructions
    /// collapse away once read.
    private var connectSection: some View {
        Section {
            HStack(spacing: Theme.Space.m) {
                Circle()
                    .fill(streamer.status.tint)
                    .frame(width: 10, height: 10)
                Text(streamer.status.displayName)
                    .font(.callout)
                Spacer()
                if let ip = wifiIP {
                    Text(ip)
                        .font(.callout.monospacedDigit().bold())
                        .textSelection(.enabled)
                }
            }
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
        } header: {
            Text("Connect")
        }
    }

    // MARK: - Camera

    private var cameraSection: some View {
        Section {
            Picker("Lens", selection: $streamer.selectedLens) {
                ForEach(streamer.availableLenses) { lens in
                    Text(lens.label).tag(lens)
                }
            }

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

            Picker("Codec", selection: $streamer.codec) {
                // HDR and Apple Log are HEVC-only; offering H.264 would
                // let the picker pick a value the didSet immediately
                // reverts.
                if streamer.colorSetting == .sdr {
                    Text(VideoCodec.h264.label).tag(VideoCodec.h264)
                }
                if VideoEncoder.isSupported(.hevc) {
                    Text(VideoCodec.hevc.label).tag(VideoCodec.hevc)
                }
            }

            // Hidden on devices that can't encode Main10 — a choice that
            // can never work is worse than none (only "Standard" would
            // remain). Apple Log appears only when some lens actually
            // has a Log capture format (iOS 17+).
            if VideoEncoder.hdrSupported {
                Picker("Color", selection: $streamer.colorSetting) {
                    Text("Standard").tag(StreamColor.sdr)
                    Text("HDR (HLG)").tag(StreamColor.hlg)
                    if CameraManager.appleLogCaptureAvailable {
                        Text("Apple Log").tag(StreamColor.log)
                    }
                }
                // Green screen forces Standard: disabled, not hidden —
                // a vanished row reads as a lost feature, a greyed one
                // as a constraint (the Documentation sheet explains).
                .disabled(streamer.greenScreenEnabled)
            }

            Toggle("Green screen", isOn: $streamer.greenScreenEnabled)

            if streamer.cameraPermissionDenied || streamer.micPermissionDenied {
                Button("Camera access denied — open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }

            Button {
                Task { await streamer.start() }
            } label: {
                ActionRowLabel(title: "Start camera stream",
                               systemImage: "video.fill")
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        } header: {
            // Sections are pure controls; every explanation lives in
            // the Documentation sheet (tail row).
            Text("Camera & color")
        }
    }

    // MARK: - Microphone

    /// Moved up from Options: mic role is a per-stream decision, not a
    /// set-and-forget behaviour toggle, so it earns main-screen space.
    private var micSection: some View {
        Section {
            Toggle("Send phone mic to OBS",
                   isOn: $streamer.sendMicAudio)
            Toggle("Auto lip-sync reference",
                   isOn: $streamer.sendAudioReference)
        } header: {
            Text("Microphone")
        }
    }

    // MARK: - Screen mirror

    @State private var extensionStatus = ""

    /// Same shape as the camera module: content, then one full-width
    /// action button. The button face is ours; the (invisible) system
    /// broadcast picker stretched over it receives the tap, because iOS
    /// won't start a broadcast any other way.
    private var screenMirrorSection: some View {
        Section {
            // Surface a broken extension unconditionally (sideloading can
            // silently drop it); the healthy state and the broadcast-link
            // probe live in Options → Diagnostics.
            if !extensionStatus.isEmpty && !extensionStatus.hasPrefix("✓") {
                Text(extensionStatus)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            ZStack {
                ActionRowLabel(title: "Start screen broadcast",
                               systemImage: "rectangle.on.rectangle")
                BroadcastPickerOverlay()
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        } header: {
            Text("Screen mirror")
        }
        .onAppear {
            // Whether the extension survived sideloading — the broadcast
            // picker can show a stale entry even when it didn't.
            extensionStatus = BroadcastProbe.installedExtensionDescription()
        }
    }

    // MARK: - Tail (Options / About)

    /// Two compact rows close the form: the Options sheet (remote start,
    /// dim, effects, tally, diagnostics — each explained in place there,
    /// not in a footer here) and the GitHub link. TestFlight testers otherwise have no
    /// pointer to the plugin/docs/issues; the version line gives bug
    /// reports a build to cite.
    private var tailSection: some View {
        Section {
            Button {
                showOptions = true
            } label: {
                HStack {
                    Label {
                        Text("Options")
                    } icon: {
                        Image(systemName: "gearshape")
                            .foregroundColor(Theme.accent)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                showDocs = true
            } label: {
                HStack {
                    Label {
                        Text("Documentation")
                    } icon: {
                        Image(systemName: "book")
                            .foregroundColor(Theme.accent)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Link(destination: Self.reportProblemURL) {
                Label("Report a problem", systemImage: "ladybug")
            }
            Link(destination: URL(string: "https://github.com/MyNamesEMurray/LensLink")!) {
                Label("LensLink on GitHub", systemImage: "link")
            }
        } footer: {
            // The one surviving footer: bug reports need a build to cite,
            // and the version has no control it could live beside.
            Text(Self.versionLine)
        }
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

/// The one action-button face used by every module, so "Start camera
/// stream" and "Start screen broadcast" read as the same kind of control.
private struct ActionRowLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.body.weight(.semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.accent,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
    }
}
