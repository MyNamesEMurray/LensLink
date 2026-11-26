import SwiftUI

/// Documentation → Settings: one entry per behaviour control in the
/// Settings and Camera sheets, grouped by what the control changes.
/// Pause is here too: it has no toggle, but it shapes how a stream
/// behaves.
struct OptionsDocumentationView: View {
    var body: some View {
        Form {
            Section {
                Text("**Focus on faces** keeps focus and exposure on the faces the camera sees while focus is on auto, the way the Camera app does — a tap on the picture outranks it until the scene changes, and a lock ignores it. Off, the camera weights the centre of the frame.")
                Text("**Natural motion blur**, on by default, stops auto exposure from running the shutter slower than half the frame interval (the 180° rule: 1/60 at 30 fps), so movement doesn't smear in a dim room; ISO rises instead. The same switch is on the adjust tray's Shutter chip and in the web panel.")
                Text(SettingInfo.stabilization)
                Text(SettingInfo.reframe)
            } header: {
                Text("Camera behavior")
            }

            Section {
                Text(SettingInfo.remoteStart)
            } header: {
                Text("Remote start")
            }

            Section {
                Text(SettingInfo.idleView)
            } header: {
                Text("Idle view")
            }

            Section {
                Text("**Pause** holds a stream without ending it — the phone stays connected, the camera stays on, and OBS shows a dimmed, blurred still with a pause symbol instead of a frozen picture. The pause button sits on the Live screen next to Stop, and the same control is in OBS (source properties) and the web panel. Audio keeps going, so the phone can still be your microphone while the picture is held.")
            } header: {
                Text("Streaming")
            }

            Section {
                Text(SettingInfo.remember)
            } header: {
                Text("Remembered settings")
            }

            Section {
                Text("**120 and 240 fps** are experimental and appear in the frame rate list where this camera has them (1080p and 720p on recent iPhones; 240 uses a sensor-binned format). The stream's bitrate grows with them, the phone runs hotter and drains faster, and an OBS canvas set to 60 shows every other frame at best — set the canvas to match, and prefer USB.")
                Text(SettingInfo.videoEffects)
            } header: {
                Text("Experimental")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
