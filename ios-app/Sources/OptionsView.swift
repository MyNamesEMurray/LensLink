import SwiftUI

/// The Options sheet: the behaviour toggles, each with its own short
/// explanation. They live off the main screen so the Setup form stays
/// compact — a single wall-of-text footer under four toggles was
/// unreadable, and pushed the form into scrolling.
struct OptionsView: View {
    @EnvironmentObject private var streamer: Streamer
    @Environment(\.dismiss) private var dismiss

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
                    Toggle("Dim screen while streaming",
                           isOn: $streamer.dimWhileStreaming)
                } footer: {
                    Text("Dims 10 seconds into streaming to save battery — tap to wake.")
                }

                Section {
                    Toggle("Send phone mic to OBS",
                           isOn: $streamer.sendMicAudio)
                    Toggle("Auto lip-sync reference",
                           isOn: $streamer.sendAudioReference)
                } header: {
                    Text("Microphone")
                } footer: {
                    // One capture, two jobs — Streamer enforces the
                    // exclusivity; this footer is where users learn it.
                    Text("**Send phone mic** makes this phone the camera's audio in OBS — a wireless mic. **Auto lip-sync** sends the mic only as a timing reference for aligning your real microphone; it's never heard. One mic, one role — turning one on turns the other off.")
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
                } footer: {
                    Text("The camera's formats and which Control Center video effects each supports — paste into a bug report if an effect is missing.")
                }
            }
            .navigationTitle("Options")
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
