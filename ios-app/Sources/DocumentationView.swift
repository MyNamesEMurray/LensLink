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
                Text("The card at the top names your computer once OBS connects, with its OBS version and whether it came in over USB or Wi-Fi. While OBS is connected and the camera is idle, its **Start** button starts the stream from here; otherwise the card shows the phone's address, which is what OBS needs.")
                Text("**Format** is one row — resolution, frame rate, codec and color — with the choices behind it. Resolution and frame rate offer only what the chosen camera supports. Codec and Color constrain each other: HDR and Apple Log are HEVC only, so picking H.264 returns Color to Standard and picking HDR or Log switches the codec to HEVC.")
                Text("**Quality**, in the Format sheet. **Balanced** streams at a bitrate that is safe on ordinary Wi-Fi and only backs off from it. **Maximum** starts higher and keeps probing upward while the connection stays clean — up to about six times the balanced rate over USB, four over Wi-Fi — backing off the moment frames queue or drop and settling just under whatever the link carries. It also switches the encoder to quality-first settings and, unless system video effects are allowed, streams from the full sensor readout rather than the binned format. More data and more heat; watch the Stats line the first time.")
            } header: {
                Text("Connecting")
            }

            Section {
                Text("**HDR (HLG)** streams 10-bit color. OBS tone-maps it for SDR scenes, and HDR canvases get the real thing.")
                Text("**Apple Log** (Pro iPhones, iOS 17+) streams a flat 10-bit image made for grading — add an **Apply LUT** filter to the source in OBS and load an Apple Log LUT.")
                Text("Both are HEVC-only and take effect when the camera next starts. Color lives in the Format sheet and only offers what this phone can capture.")
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
                Text("**Tap** the picture to focus and expose there — a yellow square marks the spot, and the camera holds that point until the scene changes, then goes back to auto. **Hold** the picture to lock focus and exposure there (AE/AF Lock): the Focus chip goes locked and the Exposure chip goes to ISO, and tapping either chip releases it. **Drag** up or down anywhere on it to brighten or darken the shot — the exposure bias, while exposure is on auto.")
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
                Text("**Focus on faces** keeps focus and exposure on the faces the camera sees while focus is on auto, the way the Camera app does — a tap on the picture outranks it until the scene changes, and a lock ignores it. Off, the camera weights the centre of the frame.")
                Text("**Remote start from OBS**: while the app is open and idle, OBS can start the camera for you. The phone stays awake while it waits — locking it or leaving the app ends remote start. Siri: \"Start streaming with LensLink.\"")
                Text("**Idle view** is what the Live screen becomes 10 seconds after you last touch it, for a phone that's mounted and out of reach. **Standard** leaves the controls up. **Clean feed** hides everything but the picture — turn Stats on (status pill) before you stop touching it to keep the health readout. **Dim screen** blanks the screen and drops the brightness to save battery, and is the only one that also dims remote-start standby, a minute in. Any tap brings the controls back.")
                Text("**Pause** holds a stream without ending it — the phone stays connected, the camera stays on, and OBS shows a dimmed, blurred still with a pause symbol instead of a frozen picture. The pause button sits on the Live screen next to Stop, and the same control is in OBS (source properties) and the web panel. Audio keeps going, so the phone can still be your microphone while the picture is held.")
                Text("**High frame rate** is experimental: it adds 120 and 240 fps to the Format sheet where this camera has them (1080p and 720p on recent iPhones; 240 uses a sensor-binned format). The stream's bitrate grows with it, the phone runs hotter and drains faster, and an OBS canvas set to 60 shows every other frame at best — set the canvas to match, and prefer USB. Turning it off drops the rate back to 60.")
                Text("**Remember camera settings** keeps each camera's exposure, white balance, zoom and focus from one stream to the next — a shot dialled in once stays dialled in, per lens. Turn it off and every camera starts on auto, and what was stored is forgotten.")
                Text("**Allow system video effects** is experimental: it lets iOS lower the frame rate on its own, which the Control Center video effects (Portrait, Studio Light) may require. Takes effect when the camera next starts.")
            } header: {
                Text("Options")
            }

            Section {
                Text("The colored border around the Live screen while streaming. Colors, priority order, and per-status off switches are customizable in Options → Tally light. The wave button beside a color makes that status pulse instead of holding steady — motion catches the eye for something you're meant to notice without watching for it.")
                Text(markdown: L("**Low battery** is one of the statuses you can light: it turns on with iOS Low Power Mode, or at %lld%% and below, and clears the moment you plug in. While the screen is dimmed the battery level also shows large under the wake hint — so a phone across the room can be read at a glance, without touching it.", 20))
            } header: {
                Text("Tally light")
            }

            Section {
                Text("**Camera diagnostics** lists the camera's formats — which resolutions support the Control Center video effects, and which are 10-bit HDR or Apple Log capable. Paste it into a bug report if something is missing.")
            } header: {
                Text("Diagnostics")
            }

            Section {
                Text("**VoiceOver** and **Switch Control**: while either is on, the Live screen never dims or hides its controls by itself, and remote-start standby never dims. The status pill's menu still does it when you ask. VoiceOver also says when the stream goes live, pauses, goes on air, loses its connection to OBS, or locks lip-sync.")
                Text("**Differentiate Without Color** (iOS Settings, Accessibility) adds the lit tally status's name as a small badge at the top of the Live screen, so the border never has to be read by its color alone.")
            } header: {
                Text("Accessibility")
            }
        }
        .navigationTitle("Documentation")
        .navigationBarTitleDisplayMode(.inline)
    }
}
