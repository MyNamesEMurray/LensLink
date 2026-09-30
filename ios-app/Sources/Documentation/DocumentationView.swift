import SwiftUI

/// The in-app manual's index. Every explanation that used to sit under
/// a control as footer text lives on one of the pages this list opens,
/// grouped by feature, so the Setup form and Options stay pure controls.
/// The root holds no prose — a title and one line per page — and each
/// page is a plain native Form of short sections (docs/UI_DESIGN.md
/// vocabulary still applies). ContentView presents this inside a
/// NavigationView sheet and supplies the Done button; pushed pages get
/// the ordinary back button.
struct DocumentationView: View {
    /// The website's manual is the long form: install, the OBS side, the
    /// web panel, troubleshooting. Kept a secondary row — the app's own
    /// pages are the manual you can read with no connection.
    private static let websiteURL = URL(string: "https://lenslink.cam/docs/")!

    var body: some View {
        Form {
            Section {
                DocumentationLink(L("Getting connected"),
                                  subtitle: L("OBS, USB, Wi-Fi and formats"),
                                  systemImage: "wifi", color: Theme.accent) {
                    ConnectingDocumentationView()
                }
            } header: {
                Text("Get started")
            }

            Section {
                DocumentationLink(L("Camera & picture"),
                                  subtitle: L("HDR, Apple Log and green screen"),
                                  systemImage: "camera.filters",
                                  color: Theme.cameraYellow) {
                    CameraDocumentationView()
                }
                DocumentationLink(L("Using the camera"),
                                  subtitle: L("Controls, focus and exposure"),
                                  systemImage: "camera.viewfinder",
                                  color: Theme.connectAmber) {
                    LiveCameraDocumentationView()
                }
            } header: {
                Text("Camera")
            }

            Section {
                DocumentationLink(L("Audio"),
                                  subtitle: L("Microphones and lip-sync"),
                                  systemImage: "mic.fill",
                                  color: Theme.liveGreen) {
                    AudioDocumentationView()
                }
                DocumentationLink(L("Screen mirroring"),
                                  subtitle: L("Broadcast your screen and app audio"),
                                  systemImage: "rectangle.on.rectangle",
                                  color: Theme.tallyPurple) {
                    ScreenMirrorDocumentationView()
                }
            } header: {
                Text("Streaming")
            }

            Section {
                DocumentationLink(L("Options"),
                                  subtitle: L("Streaming behavior and preferences"),
                                  systemImage: "gearshape.fill",
                                  color: Theme.idleGrey) {
                    OptionsDocumentationView()
                }
                DocumentationLink(L("Tally light"),
                                  subtitle: L("Status indicators and low-battery alerts"),
                                  systemImage: "lightbulb.fill",
                                  color: Theme.tallyLive) {
                    TallyDocumentationView()
                }
            } header: {
                Text("Settings")
            }

            Section {
                DocumentationLink(L("Accessibility & diagnostics"),
                                  subtitle: L("Accessibility features and camera diagnostics"),
                                  systemImage: "eye.fill",
                                  color: Color(hex: 0x5E5CE6)) {
                    AccessibilityDocumentationView()
                }
            } header: {
                Text("Help")
            }

            Section {
                Link(destination: Self.websiteURL) {
                    HStack {
                        Text("Full LensLink documentation")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundColor(.secondary)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .navigationTitle("Documentation")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One index row: the Settings app's icon tile, the page's name, and a
/// line saying what's on it, behind a plain NavigationLink so the
/// system supplies the disclosure chevron, the highlight, and the single
/// VoiceOver element (name, then description, then "button"). No fixed
/// height — at accessibility text sizes the description simply wraps.
private struct DocumentationLink<Destination: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let color: Color
    let destination: Destination

    init(_ title: String, subtitle: String, systemImage: String, color: Color,
         @ViewBuilder destination: () -> Destination) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.color = color
        self.destination = destination()
    }

    var body: some View {
        NavigationLink(destination: destination) {
            SettingsRowLabel(title, systemImage: systemImage, color: color,
                             subtitle: subtitle)
        }
    }
}
