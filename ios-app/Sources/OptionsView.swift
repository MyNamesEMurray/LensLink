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
                    Toggle("Dim screen to save battery",
                           isOn: $streamer.dimWhileStreaming)
                } footer: {
                    Text("Dims 10 seconds into streaming, or a minute into remote-start standby — tap to wake. Never while you're using the app.")
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
                    Toggle("Allow system video effects",
                           isOn: $streamer.allowVideoEffects)
                } footer: {
                    Text("Experimental: lets iOS lower the frame rate on its own, which the Control Center video effects (Portrait, Studio Light) may require. Takes effect when the camera next starts.")
                }

                // Hidden entirely on devices that can't encode Main10 —
                // a choice that can never work is worse than none (only
                // "Standard" would remain). Apple Log appears only when
                // some lens actually has a Log capture format (iOS 17+).
                if VideoEncoder.hdrSupported {
                    Section {
                        Picker("Color", selection: $streamer.colorSetting) {
                            Text("Standard").tag(StreamColor.sdr)
                            Text("HDR (HLG)").tag(StreamColor.hlg)
                            if CameraManager.appleLogCaptureAvailable {
                                Text("Apple Log").tag(StreamColor.log)
                            }
                        }
                    } footer: {
                        if CameraManager.appleLogCaptureAvailable {
                            // Three sentences covering two choices — the
                            // sanctioned exception (docs/UI_DESIGN.md).
                            Text("HDR streams 10-bit HLG color — OBS tone-maps it for SDR scenes. Apple Log streams a flat 10-bit image made for grading with a LUT in OBS; both are HEVC-only and take effect when the camera next starts.")
                        } else {
                            Text("HDR streams 10-bit HLG color — OBS tone-maps it for SDR scenes, and HDR canvases get the real thing. HEVC only; takes effect when the camera next starts.")
                        }
                    }
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
