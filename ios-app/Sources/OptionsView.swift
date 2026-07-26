import SwiftUI

/// The Options sheet: the set-and-forget behaviour toggles plus the
/// diagnostics, each with its own short explanation. They live off the
/// main screen so the Setup form stays focused on per-stream decisions
/// (camera, color, mic role) — a single wall-of-text footer under a
/// pile of toggles was unreadable, and pushed the form into scrolling.
struct OptionsView: View {
    @EnvironmentObject private var streamer: Streamer
    @Environment(\.dismiss) private var dismiss

    // Screen-mirror diagnostics (Diagnostics section below).
    @State private var probeResult: String?
    @State private var extensionStatus = ""

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Toggle("Remote start from OBS",
                           isOn: $streamer.remoteStartEnabled)
                } footer: {
                    Text("While the app is open and idle, OBS can start the camera for you. The phone stays awake while it waits — locking it or leaving the app ends remote start. Siri: \"Start streaming with LensLink.\"")
                }

                Section {
                    Toggle("Dim screen to save battery",
                           isOn: $streamer.dimWhileStreaming)
                } footer: {
                    Text("Dims 10 seconds into streaming, or a minute into remote-start standby — tap to wake. Never while you're using the app.")
                }

                Section {
                    Toggle("Allow system video effects",
                           isOn: $streamer.allowVideoEffects)
                } footer: {
                    Text("Experimental: lets iOS lower the frame rate on its own, which the Control Center video effects (Portrait, Studio Light) may require. Takes effect when the camera next starts.")
                }

                Section {
                    NavigationLink(destination: TallyLightOptionsView()) {
                        Text("Tally light")
                    }
                } footer: {
                    Text("The colored border around the Live screen while streaming.")
                }

                Section {
                    NavigationLink(destination: CameraDiagnosticsView()) {
                        Text("Camera diagnostics")
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
                            Text("Check broadcast link")
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
                } header: {
                    Text("Diagnostics")
                } footer: {
                    Text("Camera diagnostics lists the camera's formats and capabilities — paste into a bug report if an effect or color mode is missing. Check broadcast link verifies the screen-mirror extension while a broadcast is running.")
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
