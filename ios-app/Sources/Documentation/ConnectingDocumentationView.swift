import SwiftUI

/// Documentation → Getting connected: the source in OBS, the two ways
/// in (Wi-Fi, USB), the Setup screen's computer card, and the Format
/// sheet with its Quality choice.
struct ConnectingDocumentationView: View {
    var body: some View {
        Form {
            Section {
                Text("The camera streams to a **LensLink Camera** source in OBS; the screen broadcast streams to a **LensLink Screen** source. Add the source in OBS, enter the phone's Wi-Fi address as its Phone IP — or plug in USB and set Connection to \"USB cable\" (Windows needs iTunes).")
            } header: {
                Text("Connecting to OBS")
            }

            Section {
                Text("The card at the top names your computer once OBS connects, with its OBS version and whether it came in over USB or Wi-Fi. While remote start is armed and OBS is connected, its **Start** button starts the stream from here; otherwise the card shows the phone's address, which is what OBS needs.")
            } header: {
                Text("Connection")
            }

            Section {
                Text("**Format** is one row — resolution, frame rate, codec and color — with the choices behind it. Resolution and frame rate offer only what the chosen camera supports. Codec and Color constrain each other: HDR and Apple Log are HEVC only, so picking H.264 returns Color to Standard and picking HDR or Log switches the codec to HEVC.")
            } header: {
                Text("Format")
            }

            Section {
                Text("**Quality**, in the Format sheet. **Balanced** streams at a bitrate that is safe on ordinary Wi-Fi and only backs off from it. **Maximum** starts higher and keeps probing upward while the connection stays clean — up to about six times the balanced rate over USB, four over Wi-Fi — backing off the moment frames queue or drop and settling just under whatever the link carries. It also switches the encoder to quality-first settings and, unless system video effects are allowed, streams from the full sensor readout rather than the binned format. More data and more heat; watch the Stats line the first time.")
            } header: {
                Text("Quality")
            }
        }
        .navigationTitle("Getting connected")
        .navigationBarTitleDisplayMode(.inline)
    }
}
