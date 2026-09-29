import SwiftUI

/// Documentation → Screen mirroring: the LensLink Screen source, and
/// what does and doesn't come along (app audio yes, DRM audio and the
/// microphone no).
struct ScreenMirrorDocumentationView: View {
    var body: some View {
        Form {
            Section {
                Text("Streams your whole screen, with app audio, to a **LensLink Screen** source — great for mobile games or app demos. iOS mutes DRM audio (Apple Music, Netflix), and your microphone isn't sent — mic yourself in OBS as usual.")
            }
        }
        .navigationTitle("Screen mirroring")
        .navigationBarTitleDisplayMode(.inline)
    }
}
