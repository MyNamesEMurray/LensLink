import SwiftUI

/// Documentation → Accessibility & diagnostics. Camera diagnostics is a
/// dump of the camera's formats, not general troubleshooting — the
/// wording says so.
struct AccessibilityDocumentationView: View {
    var body: some View {
        Form {
            Section {
                Text("**VoiceOver** and **Switch Control**: while either is on, the Live screen never dims or hides its controls by itself, and remote-start standby never dims. The status pill's menu still does it when you ask. VoiceOver also says when the stream goes live, pauses, goes on air, loses its connection to OBS, or locks lip-sync.")
                Text("With VoiceOver, swipe up or down on the active lens button to zoom; a double-tap resets the zoom. On the green screen button, swipe up or down to move the Subject cutoff while depth assist runs, and use the Actions rotor to turn green screen on or off.")
            } header: {
                Text("Accessibility")
            }

            Section {
                Text("**Differentiate Without Color** (iOS Settings, Accessibility) adds the lit tally status's name as a small badge at the top of the Live screen, so the border never has to be read by its color alone.")
            } header: {
                Text("Differentiate Without Color")
            }

            Section {
                Text("**Camera diagnostics** lists the phone's model, each camera's lens details and exposure ranges, the zoom levels where the phone switches lenses, and every format — which resolutions support the Control Center video effects, and which are 10-bit HDR or Apple Log capable. Paste it into a bug report if something is missing.")
            } header: {
                Text("Camera diagnostics")
            }
        }
        .navigationTitle("Accessibility & diagnostics")
        .navigationBarTitleDisplayMode(.inline)
    }
}
