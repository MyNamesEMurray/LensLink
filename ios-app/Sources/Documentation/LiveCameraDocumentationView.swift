import SwiftUI

/// Documentation → Using the camera: the Live screen while streaming —
/// lenses and zoom, tap/hold/drag focus and exposure, the adjust tray,
/// and Stats.
struct LiveCameraDocumentationView: View {
    var body: some View {
        Form {
            Section {
                Text("While streaming, the screen shows the picture, the status pill, Pause and Stop, and the lens buttons.")
            } header: {
                Text("Live screen")
            }

            Section {
                Text("The lens buttons — **.5**, **1×**, **2** — switch cameras the way they do in the Camera app. Pinch to zoom within a lens. Tap the active one again to reset its zoom. A device with two front cameras gets the same buttons for the front camera.")
            } header: {
                Text("Lenses & zoom")
            }

            Section {
                Text("**Tap** the picture to focus and expose there — a yellow square marks the spot, and the camera holds that point until the scene changes, then goes back to auto. **Hold** the picture to pin focus and exposure to that spot of the frame (AE/AF Lock): wherever you point the phone, the camera keeps focusing and exposing for whatever is there, and the square stays until a tap on the picture or the Focus chip lets it go. To freeze focus and exposure instead, lock Focus and set Exposure to ISO in the tray. **Drag** up or down anywhere on it to brighten or darken the shot — the exposure bias, while exposure is on auto.")
            } header: {
                Text("Focus & exposure")
            }

            Section {
                Text("The **chevron** opens the adjust tray: one dial, and a chip for each thing it can drive — Zoom, Exposure, Shutter, WB, Focus, and Subject while green screen runs with depth assist. A yellow **A** on a chip means that setting is on auto. Drag the dial and it goes manual; tap the active chip again and it goes back to auto. Exposure on auto is the bias dial; drag Shutter to take exposure manual, and the Exposure chip becomes ISO. Flashlight and Flip sit in the tray too.")
            } header: {
                Text("Adjust tray")
            }

            Section {
                Text("Tap the **status pill** for Stats — a health line of fps, Mb/s and dropped frames — and, when an idle view is set, to engage it now instead of waiting 10 seconds.")
            } header: {
                Text("Stats")
            }
        }
        .navigationTitle("Using the camera")
        .navigationBarTitleDisplayMode(.inline)
    }
}
