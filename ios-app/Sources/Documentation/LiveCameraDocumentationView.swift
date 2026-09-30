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
                Text("**Tap** the picture to focus and expose there — a yellow square marks the spot, and the camera holds that point until the scene changes, then goes back to auto. **Hold** the picture to lock focus and exposure there (AE/AF Lock): the Focus chip goes locked and the Exposure chip goes to ISO, and tapping either chip releases it. **Drag** up or down anywhere on it to brighten or darken the shot — the exposure bias, while exposure is on auto.")
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
