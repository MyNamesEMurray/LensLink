import SwiftUI

/// The Settings sheet: how the app behaves (Live screen, remote start)
/// and Help. Everything that shapes the picture is in the Camera sheet
/// instead, so a setting sits beside the choices that limit it. No
/// footer text anywhere — every explanation lives in DocumentationView,
/// so both surfaces stay pure controls.
struct OptionsView: View {
    @EnvironmentObject private var streamer: Streamer
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var tallySettings = TallySettings.shared

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Toggle(isOn: $streamer.proInterface) {
                        SettingsRowLabel(L("Pro interface"),
                                         systemImage: "slider.horizontal.below.rectangle",
                                         color: Theme.accent,
                                         info: SettingInfo.proInterfaceTip)
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
                                         color: Color(hex: 0x5E5CE6),
                                         info: SettingInfo.idleViewTip)
                    }
                    NavigationLink(destination: TallyLightOptionsView()) {
                        HStack {
                            SettingsRowLabel(L("Tally light"),
                                             systemImage: "lightbulb.fill",
                                             color: Theme.tallyLive)
                            Spacer()
                            if tallyOff {
                                Text("Off")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Live screen")
                }

                Section {
                    Toggle(isOn: $streamer.armOnOpen) {
                        SettingsRowLabel(L("Arm remote start on open"),
                                         systemImage: "play.fill",
                                         color: Theme.liveGreen,
                                         info: SettingInfo.remoteStartTip)
                    }
                } header: {
                    Text("Remote start")
                }

                Section {
                    NavigationLink(destination: DocumentationView()) {
                        SettingsRowLabel(L("Documentation"), systemImage: "book.fill",
                                         color: Theme.accent)
                    }
                    NavigationLink(destination: CameraDiagnosticsView()) {
                        SettingsRowLabel(L("Camera diagnostics"),
                                         systemImage: "list.bullet.rectangle",
                                         color: Theme.idleGrey)
                    }
                    Link(destination: Self.reportProblemURL) {
                        SettingsRowLabel(L("Report a problem"), systemImage: "ladybug.fill",
                                         color: Theme.errorRed)
                    }
                    Link(destination: URL(string: "https://github.com/MyNamesEMurray/LensLink")!) {
                        SettingsRowLabel(L("LensLink on GitHub"), systemImage: "link",
                                         color: Theme.idleGrey)
                    }
                } header: {
                    Text("Help")
                } footer: {
                    // Bug reports need a build to cite.
                    Text(Self.versionLine)
                }
            }
            .navigationTitle("Settings")
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
    fileprivate var tallyOff: Bool {
        tallySettings.entries.allSatisfy { $0.color == TallyColor.none }
    }

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
        // TestFlight builds carry a sandbox receipt and App Store builds a
        // production one; prefill the install dropdown so reports say
        // which distribution they came from.
        if let receipt = Bundle.main.appStoreReceiptURL {
            if receipt.lastPathComponent == "sandboxReceipt" {
                items.append(URLQueryItem(name: "install", value: "TestFlight"))
            } else if FileManager.default.fileExists(atPath: receipt.path) {
                items.append(URLQueryItem(name: "install", value: "App Store"))
            }
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
