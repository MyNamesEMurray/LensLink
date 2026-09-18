import SwiftUI

/// The Options sheet: the set-and-forget behaviour toggles plus the
/// diagnostics. They live off the main screen so the Setup form stays
/// focused on per-stream decisions (camera, color, mic role). No footer
/// text anywhere — every explanation lives in DocumentationView, so
/// both surfaces stay pure controls.
struct OptionsView: View {
    @EnvironmentObject private var streamer: Streamer
    @Environment(\.dismiss) private var dismiss
    // For the tally row's value: which statuses light it. Read-only
    // here; its screen edits it.
    @ObservedObject private var tallySettings = TallySettings.shared

    // Screen-mirror diagnostics (Diagnostics section below).
    @State private var probeResult: String?
    @State private var extensionStatus = ""

    var body: some View {
        NavigationView {
            Form {
                // The behaviours, in the order they matter during a
                // stream; each row wears the Settings app's icon tile
                // (SettingsRowLabel) so this sheet and the Setup screen
                // read as one list style.
                Section {
                    Toggle(isOn: $streamer.remoteStartEnabled) {
                        SettingsRowLabel("Remote start from OBS",
                                         systemImage: "play.fill",
                                         color: Theme.liveGreen)
                    }
                    // What the Live screen becomes 10 seconds after you
                    // stop touching it. Inline picker: three short labels
                    // that fit one row and read as one choice, where a
                    // pushed screen would hide two of the three.
                    Picker(selection: $streamer.idleAppearance) {
                        ForEach(Streamer.IdleAppearance.allCases) { view in
                            Text(view.displayName).tag(view)
                        }
                    } label: {
                        SettingsRowLabel("Idle view", systemImage: "moon.fill",
                                         color: Color(hex: 0x5E5CE6))
                    }
                    Toggle(isOn: $streamer.faceFocus) {
                        SettingsRowLabel("Focus on faces",
                                         systemImage: "face.smiling",
                                         color: Theme.cameraYellow)
                    }
                    // Hidden where iOS won't grant background capture at
                    // all: a toggle that can't do anything is worse than
                    // no toggle.
                    if streamer.backgroundStreamingAvailable {
                        Toggle(isOn: $streamer.backgroundStreaming) {
                            SettingsRowLabel("Keep streaming in the background",
                                             systemImage: "rectangle.on.rectangle",
                                             color: Theme.accent)
                        }
                    }
                    NavigationLink(destination: TallyLightOptionsView()) {
                        HStack {
                            SettingsRowLabel("Tally light",
                                             systemImage: "lightbulb.fill",
                                             color: Theme.tallyLive)
                            Spacer()
                            Text(tallySummary)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Toggle(isOn: $streamer.rememberCameraSettings) {
                        SettingsRowLabel("Remember camera settings",
                                         systemImage: "clock.arrow.circlepath",
                                         color: Theme.connectAmber)
                    }
                }

                Section {
                    Toggle(isOn: $streamer.highFrameRate) {
                        SettingsRowLabel("High frame rate",
                                         systemImage: "speedometer",
                                         color: Theme.idleGrey)
                    }
                    Toggle(isOn: $streamer.allowVideoEffects) {
                        SettingsRowLabel("Allow system video effects",
                                         systemImage: "wand.and.stars",
                                         color: Theme.idleGrey)
                    }
                    NavigationLink(destination: CameraDiagnosticsView()) {
                        SettingsRowLabel("Camera diagnostics",
                                         systemImage: "list.bullet.rectangle",
                                         color: Theme.idleGrey)
                    }

                    // The screen-mirror tools, moved here from the main
                    // screen's Screen mirror section (a broken extension
                    // still warns there unconditionally).
                    // Diagnostic: verifies the broadcast extension's
                    // listener is reachable on-device, independent of
                    // OBS/USB. Run it while a broadcast is active.
                    Button {
                        probeResult = "Checking…"
                        BroadcastProbe.run { result in
                            switch result {
                            case .screenListener:
                                probeResult = "✓ Broadcast link is up — OBS should be able to connect"
                            case .appListener:
                                probeResult = "✗ Only the app's own listener answered — start a screen broadcast, then run this again"
                            case .none:
                                probeResult = "✗ No listener — is a screen broadcast running? If yes, the extension isn't working"
                            }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            SettingsRowLabel("Check broadcast link",
                                             systemImage: "antenna.radiowaves.left.and.right",
                                             color: Theme.idleGrey)
                            Text(extensionStatus)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if let probeResult {
                                Text(probeResult)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Options")
            .onAppear {
                // Whether the extension survived sideloading — the
                // broadcast picker can show a stale entry even when it
                // didn't.
                extensionStatus =
                    BroadcastProbe.installedExtensionDescription()
            }
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
}

extension OptionsView {
    /// "On air, In preview" — the statuses that light the border, in
    /// priority order; "Off" when none does.
    fileprivate var tallySummary: String {
        let lit = tallySettings.entries
            .filter { $0.color != TallyColor.none }
            .map { $0.status.displayName }
        return lit.isEmpty ? "Off" : lit.joined(separator: ", ")
    }
}

/// The camera's format table with the system video-effect flags, built
/// on demand and copyable — so "the Video Effects panel is empty on my
/// phone" can be diagnosed from a paste instead of a Mac-tethered log.
private struct CameraDiagnosticsView: View {
    private let report = CameraManager.formatReport()
    @State private var copied = false

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            Text(report)
                .font(.system(.caption2, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle("Camera diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(copied ? "Copied" : "Copy") {
                    UIPasteboard.general.string = report
                    copied = true
                }
            }
        }
    }
}
