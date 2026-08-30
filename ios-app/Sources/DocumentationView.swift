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
                Text("**Green screen** keeps you in the picture and paints everything else solid green before the video leaves the phone — turning it on sets Color to Standard. The **LensLink Camera** source in OBS adds a ready-tuned filter that keys the green out; it's added once, so deleting or re-tuning it in OBS sticks.")
                Text("**Depth assist** sharpens the cutout with real depth — the front camera on Face ID phones, or the rear Main lens on Pro (LiDAR) phones. Other lenses use shape detection alone, which keeps every person in frame. It also turns off Center Stage and the other system video effects.")
                Text("**Subject distance** appears on the Live screen while depth assist runs: anything farther than the distance becomes background — the way to drop a passer-by behind you. Tap the readout to go back to **All** (no limit).")
            } header: {
                Text("Green screen")
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
                Text("**Idle view** is what the Live screen becomes 10 seconds after you last touch it, for a phone that's mounted and out of reach. **Standard** leaves the controls up. **Clean feed** hides everything but the picture — turn Stats on before you stop touching it to keep the health readout. **Dim screen** blanks the screen and drops the brightness to save battery, and is the only one that also dims remote-start standby, a minute in. Any tap brings the controls back.")
                Text("**Allow system video effects** is experimental: it lets iOS lower the frame rate on its own, which the Control Center video effects (Portrait, Studio Light) may require. Takes effect when the camera next starts.")
            } header: {
                Text("Options")
            }

            Section {
                Text("The colored border around the Live screen while streaming. Colors, priority order, and per-status off switches are customizable in Options → Tally light, and any status can pulse instead of holding steady.")
                Text("**Low battery** is one of the statuses you can light: it turns on with iOS Low Power Mode, or at 20% and below, and clears the moment you plug in. While the screen is dimmed the battery level also shows as a percentage under the wake hint — so a phone across the room can be checked without touching it.")
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
