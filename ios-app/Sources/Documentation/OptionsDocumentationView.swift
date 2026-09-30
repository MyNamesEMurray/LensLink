import SwiftUI

/// Documentation → Options: one entry per control in the Options
/// sheet, grouped by what the control changes. Pause is here too: it
/// has no Options toggle, but it shapes how a stream behaves.
struct OptionsDocumentationView: View {
    var body: some View {
        Form {
            Section {
                Text("**Focus on faces** keeps focus and exposure on the faces the camera sees while focus is on auto, the way the Camera app does — a tap on the picture outranks it until the scene changes, and a lock ignores it. Off, the camera weights the centre of the frame.")
            } header: {
                Text("Camera behavior")
            }

            Section {
                Text("**Remote start from OBS**: while the app is open and idle, OBS can start the camera for you. The phone stays awake while it waits — locking it or leaving the app ends remote start. Siri: \"Start streaming with LensLink.\"")
            } header: {
                Text("Remote start")
            }

            Section {
                Text("**Idle view** is what the Live screen becomes 10 seconds after you last touch it, for a phone that's mounted and out of reach. **Standard** leaves the controls up. **Clean feed** hides everything but the picture — turn Stats on (status pill) before you stop touching it to keep the health readout. **Dim screen** blanks the screen and drops the brightness to save battery, and is the only one that also dims remote-start standby, a minute in. Any tap brings the controls back.")
            } header: {
                Text("Idle view")
            }

            Section {
                Text("**Pause** holds a stream without ending it — the phone stays connected, the camera stays on, and OBS shows a dimmed, blurred still with a pause symbol instead of a frozen picture. The pause button sits on the Live screen next to Stop, and the same control is in OBS (source properties) and the web panel. Audio keeps going, so the phone can still be your microphone while the picture is held.")
            } header: {
                Text("Streaming")
            }

            Section {
                Text("**Remember camera settings** keeps each camera's exposure, white balance, zoom and focus from one stream to the next — a shot dialled in once stays dialled in, per lens. Turn it off and every camera starts on auto, and what was stored is forgotten.")
            } header: {
                Text("Remembered settings")
            }

            Section {
                Text("**High frame rate** is experimental: it adds 120 and 240 fps to the Format sheet where this camera has them (1080p and 720p on recent iPhones; 240 uses a sensor-binned format). The stream's bitrate grows with it, the phone runs hotter and drains faster, and an OBS canvas set to 60 shows every other frame at best — set the canvas to match, and prefer USB. Turning it off drops the rate back to 60.")
                Text("**Allow system video effects** is experimental: it lets iOS lower the frame rate on its own, which the Control Center video effects (Portrait, Studio Light) may require. Takes effect when the camera next starts.")
            } header: {
                Text("Experimental")
            }
        }
        .navigationTitle("Options")
        .navigationBarTitleDisplayMode(.inline)
    }
}
