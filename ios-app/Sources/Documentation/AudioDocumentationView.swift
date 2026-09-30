import SwiftUI

/// Documentation → Audio: the phone as a wireless mic, which mic, and
/// the lip-sync reference that is never heard.
struct AudioDocumentationView: View {
    var body: some View {
        Form {
            Section {
                Text("**Send phone mic** makes this phone the camera's audio in OBS — a wireless mic. The **Microphone** row beneath it picks which one — Auto follows iOS's own routing; a headset or Bluetooth mic takes over on its own.")
            } header: {
                Text("Microphone")
            }

            Section {
                Text("**Auto lip-sync** sends the mic only as a timing reference for aligning your real microphone; it's never heard.")
                Text("One mic, one role — turning one on turns the other off.")
            } header: {
                Text("Lip-sync")
            }
        }
        .navigationTitle("Audio")
        .navigationBarTitleDisplayMode(.inline)
    }
}
