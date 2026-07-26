import SwiftUI

/// The in-app manual: every explanation that used to sit under a
/// section as footer text lives here instead, grouped by feature, so
/// the Setup form and Options stay pure controls. One place to read,
/// one place to keep the wording in sync (docs/UI_DESIGN.md vocabulary
/// still applies).
struct DocumentationView: View {
    var body: some View {
        Form {
            Section {
                Text("The camera streams to a **LensLink Camera** source in OBS; the screen broadcast streams to a **LensLink Screen** source. Add the source in OBS, enter the phone's Wi-Fi address as its Phone IP — or plug in USB and set Connection to \"USB cable\" (Windows needs iTunes).")
            } header: {
                Text("Connecting")
            }

            Section {
                Text("**HDR (HLG)** streams 10-bit color. OBS tone-maps it for SDR scenes, and HDR canvases get the real thing.")
                Text("**Apple Log** (Pro iPhones, iOS 17+) streams a flat 10-bit image made for grading — add an **Apply LUT** filter to the source in OBS and load an Apple Log LUT.")
                Text("Both are HEVC-only and take effect when the camera next starts. The Color row only offers what this phone can capture.")
            } header: {
                Text("Color")
            }

            Section {
                Text("**Send phone mic** makes this phone the camera's audio in OBS — a wireless mic.")
                Text("**Auto lip-sync** sends the mic only as a timing reference for aligning your real microphone; it's never heard.")
                Text("One mic, one role — turning one on turns the other off.")
            } header: {
                Text("Microphone")
            }

            Section {
                Text("Streams your whole screen, with app audio, to a **LensLink Screen** source — great for mobile games or app demos. iOS mutes DRM audio (Apple Music, Netflix), and your microphone isn't sent — mic yourself in OBS as usual.")
            } header: {
                Text("Screen mirror")
            }

            Section {
                Text("**Remote start from OBS**: while the app is open and idle, OBS can start the camera for you. The phone stays awake while it waits — locking it or leaving the app ends remote start. Siri: \"Start streaming with LensLink.\"")
                Text("**Dim screen to save battery**: dims 10 seconds into streaming, or a minute into remote-start standby — tap to wake. Never while you're using the app.")
                Text("**Allow system video effects** is experimental: it lets iOS lower the frame rate on its own, which the Control Center video effects (Portrait, Studio Light) may require. Takes effect when the camera next starts.")
            } header: {
                Text("Options")
            }

            Section {
                Text("The colored border around the Live screen while streaming. Colors, priority order, and per-status off switches are customizable in Options → Tally light.")
            } header: {
                Text("Tally light")
            }

            Section {
                Text("**Camera diagnostics** lists the camera's formats — which resolutions support the Control Center video effects, and which are 10-bit HDR or Apple Log capable. Paste it into a bug report if something is missing.")
                Text("**Check broadcast link** verifies the screen-mirror extension is alive on this phone, independent of OBS — run it while a screen broadcast is active.")
            } header: {
                Text("Diagnostics")
            }
        }
        .navigationTitle("Documentation")
        .navigationBarTitleDisplayMode(.inline)
    }
}
