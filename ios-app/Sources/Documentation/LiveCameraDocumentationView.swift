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
                Text("The lens buttons — **.5**, **1×**, **2** — switch cameras the way they do in the Camera app. Pinch to zoom within a lens, or tap the active one for a zoom dial and slide along it; the buttons move up above the dial, so the other lenses stay a tap away. Tap the active one again to reset its zoom. A device with two front cameras gets the same buttons for the front camera.")
                Text("When the Main camera has a 48 MP sensor, an extra **2** button beside **1×** uses the middle of the sensor at full detail, sharper than zooming in. Pinch and the zoom dial stop at it on the way past. Only formats that support the crop show it.")
            } header: {
                Text("Lenses & zoom")
            }

            Section {
                Text("**Tap** the picture to focus and expose there — a yellow square marks the spot, and the camera holds that point until the scene changes, then goes back to auto. **Hold** the picture to pin focus and exposure to that spot of the frame (AE/AF Lock): wherever you point the phone, the camera keeps focusing and exposing for whatever is there, and the square stays until a tap on the picture lets it go. To freeze focus and exposure instead, lock Focus and take ISO manual in the tray. **Drag** up or down anywhere on it to brighten or darken the shot — the exposure bias, while exposure is on auto.")
            } header: {
                Text("Focus & exposure")
            }

            Section {
                Text("The **chevron** opens the adjust tray: one dial, and a chip for each thing it can drive — Focus, WB, EV, ISO and Shutter. A yellow **A** on a chip means that setting is on auto. Drag the dial and it goes manual; tap the active chip again and it goes back to auto. EV is the brightness bias while exposure is on auto, and tapping it again sets it back to 0; drag ISO or Shutter to take exposure manual. EV, ISO and Shutter click between the usual stops. The buttons under the dial stay in the same place on every chip, Flashlight and Flip included.")
                Text("The **lock** in the tray's bottom row freezes the selected setting at what auto is doing right now; tap it again for auto. Hold it to lock or unlock everything at once. On the Shutter chip, the aperture button turns **Natural motion blur** on or off: auto exposure keeps the shutter at half the frame interval or faster (1/60 at 30 fps), raising ISO in dim light instead.")
                Text("On the WB chip, the **eyedropper** sets white balance from a sheet of white paper: tap it, then tap the paper in the picture. White balance locks to the paper, correcting the green or magenta tint some LED and fluorescent lights add, until WB goes back to auto. In the web panel, **Calibrate** does the same with the paper in the middle of the picture.")
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
