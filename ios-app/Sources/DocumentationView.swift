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
                Text("**Subject** appears in the Live screen's adjust tray while depth assist runs: anything farther than the distance on the dial becomes background — the way to drop a passer-by behind you. Tap the Subject chip again to go back to **All** (no limit).")
            } header: {
                Text("Green screen")
            }

            Section {
                Text("While streaming, the screen shows the picture, the status pill, Pause and Stop, and the lens buttons — **.5**, **1×**, **2** — which switch cameras the way they do in the Camera app. Pinch to zoom within a lens.")
                Text("**Tap** the picture to focus and expose there. **Drag** up or down anywhere on it to brighten or darken the shot — the exposure bias, while exposure is on auto.")
                Text("The **chevron** opens the adjust tray: one dial, and a chip for each thing it can drive — Zoom, Exposure, Shutter, WB, Focus, and Subject while green screen runs with depth assist. A yellow **A** on a chip means that setting is on auto. Drag the dial and it goes manual; tap the active chip again and it goes back to auto. Exposure on auto is the bias dial; drag Shutter to take exposure manual, and the Exposure chip becomes ISO. Flashlight and Flip sit in the tray too.")
                Text("Tap the **status pill** for Stats — a health line of fps, Mb/s and dropped frames — and, when an idle view is set, to engage it now instead of waiting 10 seconds.")
            } header: {
                Text("Live screen")
            }

            Section {
                Text("**Send phone mic** makes this phone the camera's audio in OBS — a wireless mic. The **Microphone** row beneath it picks which one — Auto follows iOS's own routing; a headset or Bluetooth mic takes over on its own.")
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
                Text("**Idle view** is what the Live screen becomes 10 seconds after you last touch it, for a phone that's mounted and out of reach. **Standard** leaves the controls up. **Clean feed** hides everything but the picture — turn Stats on (status pill) before you stop touching it to keep the health readout. **Dim screen** blanks the screen and drops the brightness to save battery, and is the only one that also dims remote-start standby, a minute in. Any tap brings the controls back.")
                Text("**Pause** holds a stream without ending it — the phone stays connected, the camera stays on, and OBS shows a dimmed, blurred still with a pause symbol instead of a frozen picture. The pause button sits on the Live screen next to Stop, and the same control is in OBS (source properties) and the web panel. Audio keeps going, so the phone can still be your microphone while the picture is held.")
                Text("**Keep streaming in the background** moves the picture into a Picture in Picture window when you leave LensLink mid-stream, which is what lets the camera keep running — iOS stops capture for an app that is nowhere on screen. The window carries no buttons of its own: tap it to come back to LensLink, and stop or pause from here, from OBS, from the web panel, or by asking Siri. Locking the phone ends the stream. Pushing the window off the side of the screen parks it, and iOS only lends the camera to a window it can see: capture pauses, the green camera dot goes out, and OBS shows the paused still until you pull the window back — then it resumes on its own.")
                Text("**Allow system video effects** is experimental: it lets iOS lower the frame rate on its own, which the Control Center video effects (Portrait, Studio Light) may require. Takes effect when the camera next starts.")
            } header: {
                Text("Options")
            }

            Section {
                Text("A **preset** saves the camera settings you re-dial every session — exposure, white balance, zoom, focus — and you choose which of those it carries. Everything it leaves out stays where it is.")
                Text("Give a preset a **camera** and it applies whenever that camera starts; mark one as the **default** and it covers any camera without its own. Options → Presets.")
                Text("Changing any of those settings by hand pauses automatic presets, so one can never overwrite an adjustment you just made — a **Presets paused** pill appears on the Live screen, and tapping it resumes and re-applies without stopping the stream.")
            } header: {
                Text("Presets")
            }

            Section {
                Text("The colored border around the Live screen while streaming. Colors, priority order, and per-status off switches are customizable in Options → Tally light. The wave button beside a color makes that status pulse instead of holding steady — motion catches the eye for something you're meant to notice without watching for it.")
                Text("**Low battery** is one of the statuses you can light: it turns on with iOS Low Power Mode, or at 20% and below, and clears the moment you plug in. While the screen is dimmed the battery level also shows large under the wake hint — so a phone across the room can be read at a glance, without touching it.")
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
