import SwiftUI

/// Documentation → Tally light: the colored border, and the low-battery
/// status.
struct TallyDocumentationView: View {
    var body: some View {
        Form {
            Section {
                Text("The colored border around the Live screen while streaming. Colors, priority order, and per-status off switches are customizable in Options → Tally light. The wave button beside a color makes that status pulse instead of holding steady — motion catches the eye for something you're meant to notice without watching for it.")
            } header: {
                Text("Colored border")
            }

            Section {
                Text(markdown: L("**Low battery** is one of the statuses you can light: it turns on with iOS Low Power Mode, or at %lld%% and below, and clears the moment you plug in. While the screen is dimmed the battery level also shows large under the wake hint — so a phone across the room can be read at a glance, without touching it.", 20))
            } header: {
                Text("Low battery")
            }
        }
        .navigationTitle("Tally light")
        .navigationBarTitleDisplayMode(.inline)
    }
}
