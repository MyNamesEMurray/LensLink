import SwiftUI

/// Documentation → Camera & picture: what the Format sheet's Color
/// choices mean, and green screen with its depth assist and Subject
/// control.
struct CameraDocumentationView: View {
    var body: some View {
        Form {
            Section {
                Text("**HDR (HLG)** streams 10-bit color. OBS tone-maps it for SDR scenes, and HDR canvases get the real thing.")
                Text("**Apple Log** (Pro iPhones, iOS 17+) streams a flat 10-bit image made for grading — add an **Apply LUT** filter to the source in OBS and load an Apple Log LUT.")
                Text("Both are HEVC-only and take effect when the camera next starts. Color lives in the Format sheet and only offers what this phone can capture.")
            } header: {
                Text("Color")
            }

            Section {
                Text("**Green screen** keeps you in the picture and paints everything else solid green before the video leaves the phone — turning it on sets Color to Standard. The **LensLink Camera** source in OBS adds a ready-tuned filter that keys the green out; it's added once, so deleting or re-tuning it in OBS sticks.")
            } header: {
                Text("Green screen")
            }

            Section {
                Text("**Depth assist** sharpens the cutout with real depth — the front camera on Face ID phones, or the rear Main lens on Pro (LiDAR) phones. Other lenses use shape detection alone, which keeps every person in frame. It also turns off Center Stage and the other system video effects.")
                Text("**Subject** appears in the Live screen's adjust tray while depth assist runs: anything farther than the distance on the dial becomes background — the way to drop a passer-by behind you. Tap the Subject chip again to go back to **All** (no limit).")
            } header: {
                Text("Depth assist")
            }
        }
        .navigationTitle("Camera & picture")
        .navigationBarTitleDisplayMode(.inline)
    }
}
