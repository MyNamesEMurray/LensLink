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

    var body: some View {
        NavigationView {
            Form {
                // The behaviours, in the order they matter during a
                // stream; each row wears the Settings app's icon tile
                // (SettingsRowLabel) so this sheet and the Setup screen
                // read as one list style.
                Section {
                    Toggle(isOn: $streamer.remoteStartEnabled) {
                        SettingsRowLabel(L("Remote start from OBS"),
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
                        SettingsRowLabel(L("Idle view"), systemImage: "moon.fill",
                                         color: Color(hex: 0x5E5CE6))
                    }
                    Toggle(isOn: $streamer.faceFocus) {
                        SettingsRowLabel(L("Focus on faces"),
                                         systemImage: "face.smiling",
                                         color: Theme.cameraYellow)
                    }
                    NavigationLink(destination: TallyLightOptionsView()) {
                        HStack {
                            SettingsRowLabel(L("Tally light"),
                                             systemImage: "lightbulb.fill",
                                             color: Theme.tallyLive)
                            Spacer()
                            Text(tallySummary)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Toggle(isOn: $streamer.rememberCameraSettings) {
                        SettingsRowLabel(L("Remember camera settings"),
                                         systemImage: "clock.arrow.circlepath",
                                         color: Theme.connectAmber)
                    }
                }

                Section {
                    Toggle(isOn: $streamer.highFrameRate) {
                        SettingsRowLabel(L("High frame rate"),
                                         systemImage: "speedometer",
                                         color: Theme.idleGrey)
                    }
                    Toggle(isOn: $streamer.allowVideoEffects) {
                        SettingsRowLabel(L("Allow system video effects"),
                                         systemImage: "wand.and.stars",
                                         color: Theme.idleGrey)
                    }
                    NavigationLink(destination: CameraDiagnosticsView()) {
                        SettingsRowLabel(L("Camera diagnostics"),
                                         systemImage: "list.bullet.rectangle",
                                         color: Theme.idleGrey)
                    }
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

extension OptionsView {
    /// "On air, In preview" — the statuses that light the border, in
    /// priority order; "Off" when none does.
    fileprivate var tallySummary: String {
        let lit = tallySettings.entries
            .filter { $0.color != TallyColor.none }
            .map { $0.status.displayName }
        return lit.isEmpty ? L("Off") : lit.joined(separator: ", ")
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
                Button(copied ? L("Copied") : L("Copy")) {
                    UIPasteboard.general.string = report
                    copied = true
                }
            }
        }
    }
}
