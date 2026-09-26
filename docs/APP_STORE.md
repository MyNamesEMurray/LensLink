# App Store submission

Everything App Review and the store listing need, kept here so a
submission is a copy-paste and a screenshot session rather than a
memory exercise. The build itself comes from the normal release
pipeline (`docs/TESTFLIGHT.md`): every stable release is already
uploaded to App Store Connect and processed; submitting for review
picks one of those builds.

App record: **LensLink Camera**, bundle id
`com.exaltedpixels.LensLinkCamera`, free, no in-app purchases, no
accounts, no analytics.

## Review notes

Paste into App Store Connect → the version → **App Review Information →
Notes**. Update the plugin release link and the demo video link before
each submission.

> **What LensLink Camera is.** It turns an iPhone or iPad into a camera
> source for OBS Studio, the open-source broadcasting app for Mac,
> Windows and Linux. The phone captures and hardware-encodes video (up
> to 4K60, HEVC or H.264, optional 10-bit HLG or Apple Log) and streams
> it over the local network or a USB cable to an OBS plugin we publish
> as open source at https://github.com/MyNamesEMurray/LensLink. Nothing
> is recorded on the phone, and no video or data leaves the user's local
> network. There is no account, no sign-in and no server of ours.
>
> **How to test.** The app needs OBS Studio with our plugin on a Mac or
> PC on the same Wi-Fi network. Steps:
> 1. Install OBS Studio 32 (https://obsproject.com).
> 2. Install the LensLink plugin from
>    https://github.com/MyNamesEMurray/LensLink/releases/latest — the
>    macOS installer (.pkg) or Windows installer (.exe) on that page.
>    Restart OBS.
> 3. In OBS: Sources → + → **LensLink Camera**. In the source's
>    properties, pick the phone from the **Phone** dropdown (found over
>    Bonjour) or type the phone's Wi-Fi address, which the app shows on
>    its Home screen.
> 4. On the phone: open LensLink Camera, allow Camera, Microphone and
>    Local Network when asked, and tap **Start Camera**. The picture
>    appears in OBS within a second or two. The Home screen's card names
>    the computer once OBS connects.
> 5. Live controls: tap the picture to focus, hold to lock, pinch to
>    zoom, and open the tray with the chevron. The same controls appear
>    at http://localhost:9980 on the computer (the plugin's control panel).
>
> A demo video showing the full flow: DEMO_VIDEO_URL
>
> If testing with OBS isn't practical, the app can be exercised alone:
> Start Camera runs the camera and shows "Waiting for OBS…", every
> camera control works against the live preview, and Stop ends it.
>
> **Screen mirroring.** "Mirror Screen" starts a ReplayKit broadcast
> through the bundled broadcast-upload extension, which streams the
> phone's screen (with app audio, never the microphone) to a **LensLink
> Screen** source in OBS. On iOS 27 and later it opens the system
> screen-sharing picker instead and the app streams the screen itself
> with ScreenCaptureKit; the button then reads "Stop Mirroring". Test it
> the same way with that source type.
>
> **Background behaviour.** The app declares one background mode,
> `screen-capture`, used only while the user is mirroring the screen to
> OBS on iOS 27 and later. Mirroring starts only from the system
> screen-sharing picker, keeps running while the user is in the app
> they are mirroring, and stops from "Stop Mirroring" in LensLink or
> from the system's screen-sharing indicator. The camera never runs in
> the background.
> Camera streaming runs only while the app is on screen: leaving it or locking
> the phone stops the stream. On iPads that allow multitasking camera
> access, streaming continues beside another app in Split View, Slide
> Over and Stage Manager. Streaming only ever runs after the user taps
> Start, the system camera indicator is on throughout, and it stops on
> Stop, on lock, or from the computer. The microphone is used only while
> streaming and only when the user turns on "Send phone mic to OBS" (a
> wireless mic) or "Auto lip-sync reference" (a timing signal the plugin
> uses to align the user's own microphone; it is never heard).
>
> **Local Network permission** is required: the plugin dials the phone
> over the LAN. Without it, the app still works over USB.
>
> **Siri / Shortcuts.** "Start streaming with LensLink" and "Stop
> streaming with LensLink" are App Intents; `lenslink://start` and
> `lenslink://stop` are the URL-scheme equivalents.
>
> **Remote start.** With "Remote start from OBS" on, OBS can start the
> camera while the app is open and idle (the app listens on TCP port
> 9979 and keeps the screen awake in that state, dimming after a minute).

## Store listing

**Name:** LensLink Camera
**Subtitle** (30 chars max): Your iPhone as an OBS camera
**Category:** Photo & Video (secondary: Utilities)
**Age rating:** 4+ (no objectionable content; the questionnaire is all
"None")
**Price:** Free
**Support URL:** https://lenslink.cam/support/
**Marketing URL:** https://lenslink.cam
**Privacy Policy URL:** https://lenslink.cam/privacy/

**Promotional text** (170 chars, editable without a new build):

> Stream your iPhone's camera to OBS Studio over Wi-Fi or USB — up to
> 4K60, HEVC, 10-bit HDR — with live controls from your computer.

**Description:**

> LensLink Camera turns your iPhone or iPad into a camera for OBS
> Studio. Mount the phone, open the app, and it appears in OBS as a
> video source over Wi-Fi or a USB cable — with the picture quality the
> phone's camera is actually capable of.
>
> **Picture first**
> - Up to 4K at 60 fps, HEVC or H.264, with 120 and 240 fps available
>   where the camera has them
> - 10-bit HDR (HLG) and Apple Log on supported iPhones
> - Balanced or Maximum quality: Maximum finds the most your connection
>   can carry
> - Every lens, with the Camera app's lens buttons
>
> **Controls that stay out of the way**
> - Tap to focus, hold to lock focus and exposure, drag for brightness,
>   pinch to zoom
> - One tray for exposure, shutter, white balance and focus, with
>   faces-first autofocus
> - The same controls in a browser panel on your computer, and in OBS
>   itself
> - Remember camera settings: a shot dialled in once stays dialled in
>
> **Built for production**
> - Remote start: OBS starts the camera while the app sits idle
> - Tally light: a colored border says when you're on air
> - Pause with a held picture instead of a frozen frame
> - Keeps streaming beside other apps on iPads that support it
> - Automatic lip-sync: the plugin measures latency and aligns your
>   real microphone
> - Virtual green screen, right on the phone
> - Mirror your whole screen with app audio
> - Siri and Shortcuts
>
> **Private by design**
> Nothing is recorded on the phone and nothing leaves your local
> network. No account, no sign-in, no analytics.
>
> Requires OBS Studio and the free, open-source LensLink plugin for
> Mac, Windows or Linux: https://lenslink.cam

**Keywords** (100 chars): obs,camera,webcam,streaming,virtual camera,4k,hevc,hdr,usb,wifi,phone camera,capture

**What's New** (first version):

> First App Store release. Everything the TestFlight beta had: 4K60
> streaming over Wi-Fi or USB, HEVC and 10-bit HDR, remote start from
> OBS, tally light, pause, automatic lip-sync, green screen, screen
> mirroring, and the redesigned Live screen.

## Screenshots

Required sets: **6.9-inch iPhone** and **13-inch iPad** (the app targets
both device families). Take them on device with the tally lit where it
matters; the Camera app's own screenshots are the reference for framing.
`tools/store-screenshots/` adds the headline and bezel and outputs the
exact store sizes; its `shots.json` names each capture.

1. `home`: the computer card naming the Mac, "OBS connected — ready",
   Camera / Format / Green screen rows.
2. `live-glance`: the picture, status pill, Pause, Stop, lens buttons,
   tally border on air. Point the camera at something worth looking at.
3. `live-tray`: the adjust tray open on Exposure, same scene.
4. `format`: the Format sheet with Quality and Color visible.
5. `options`.
6. `obs`: the phone's Live screen with the Mac visible behind it, or the
   web control panel on the phone. A Mac screenshot in the store's
   iPhone frame is not allowed.

## App Privacy questionnaire

**Data Not Collected.** The app makes no network requests except to
the user's own OBS on the local network; the only outbound links are to
GitHub (bug reports, source) and open in Safari. No analytics, no
crash reporting SDK, no identifiers.

## Export compliance

Already answered in the build: `ITSAppUsesNonExemptEncryption = false`
(plain TCP on the local network, no custom cryptography).

## Accessibility Nutrition Labels

App Store Connect → the app → **Accessibility**, once for **iPhone** and
once for **iPad** (the answers are the same on both). The rules behind
each claim are `docs/UI_DESIGN.md` §8; a change that breaks one of them
takes the label down with it. Run the matching checks below on a real
device before declaring a label, and again after any release that
touches the Live screen or the Setup screen. "Common tasks" for this app
are: connect to OBS, start the camera, adjust it while live (zoom,
exposure, focus, white balance, flashlight, flip, lens), pause, stop,
and change Options.

| Label | Declare | Why |
|---|---|---|
| VoiceOver | Yes | Every control has a spoken name and state, stream changes are announced, and idle dimming waits while VoiceOver runs. |
| Voice Control | Yes | Every control has a name Voice Control can say, with short aliases ("Stop", "Flip", "Wake"); the tray's dial reaches every setting the picture's gestures do. |
| Larger Text | Yes, after the checks pass | Every form follows Dynamic Type to the largest size; the Live screen scales its text to twice the default and shows the large content viewer on its fixed-size controls. |
| Dark Interface | Yes | The Live screen is always dark; the Setup screen and every sheet follow the system appearance. |
| Differentiate Without Color Alone | Yes | Every status has a word beside its dot, and with the setting on the tally border gains a badge naming the lit status. |
| Sufficient Contrast | Yes, on the strength of Increase Contrast | With Increase Contrast (or Reduce Transparency) on, glass over the picture turns near-opaque and secondary text near-white. The default glass over a very bright picture can dip below 4.5:1 for secondary text, so re-read Apple's current criteria before declaring; if they require the default look to pass on its own, leave this one off. |
| Reduced Motion | Yes | The tally pulse holds steady, the tray and idle view change without moving, and the focus square lands without scaling. |
| Captions | No (not applicable) | The app plays no media with speech or audio of its own. |
| Audio Descriptions | No (not applicable) | The app plays no video content. |

### Device checks before declaring

**VoiceOver** (Settings → Accessibility → VoiceOver):

- [ ] Setup: every row, the Start camera and Mirror Screen buttons (one
      element each, not two), Options and Documentation read sensibly.
- [ ] Start the camera. "Live" is spoken when OBS connects; a success
      haptic on the way.
- [ ] Live screen: swipe through the status pill (its word), Pause,
      Stop camera, lens buttons (name, current one selected with its
      zoom), Adjust camera. Open the tray: every chip (name, auto or
      manual, selected), the dial (chip name and readout as value,
      adjustable with swipe up and down; on Shutter, WB and Focus that
      takes the setting out of auto), Flashlight (value On / Off),
      Flip camera, Close.
- [ ] Pause and resume: "Paused", then "Live". Unplug or quit OBS:
      "Connection lost" plus a warning haptic; reconnect: "Live".
- [ ] Put the source in OBS's Program: "On air". With lip-sync
      auto-calibrate on: "Sync locked" when it locks.
- [ ] With Idle view on Dim screen, wait well past 10 seconds: the
      screen never dims. Use the status pill's Dim screen now, then
      double-tap the wake hint: the controls come back.
- [ ] Turn VoiceOver on while the screen is already dimmed (triple-click
      shortcut): the screen wakes.
- [ ] Remote-start standby with Dim screen: the Setup screen never dims
      while VoiceOver runs. Repeat these two with Switch Control.

**Voice Control** (Settings → Accessibility → Voice Control):

- [ ] "Show names" on the Live screen and the tray: every button has a
      name, none shows a bare number.
- [ ] "Tap Flashlight", "Tap Torch", "Tap Flip", "Tap Switch camera",
      "Tap Stop", "Tap Adjust", "Tap Close", "Tap Status", "Tap
      Exposure", "Tap Mirror Screen" all work.
- [ ] Let the Live screen dim, then "Tap Wake".

**Larger Text** (Settings → Accessibility → Display & Text Size →
Larger Text, at the largest size):

- [ ] Setup: the computer card stacks the name, status and Start or
      address without clipping; every row, the Format sheet, Options,
      Tally light and Documentation stay usable.
- [ ] Live screen: the status and sync pills, the tray's mode line and
      the dial readout are larger and nothing overlaps the top bar.
- [ ] Long-press a glass button, a dial chip, a lens button and the
      status pill: the large content viewer shows its name.

**Dark Interface**: switch Settings → Display & Brightness to Dark and
back; Setup, every sheet and the Live screen stay legible in both.

**Differentiate Without Color Alone** (Display & Text Size):

- [ ] Stream with the source on air in OBS: a badge reading "On air"
      sits under the top bar, still visible on the dimmed screen.
      Preview it: "In preview".
- [ ] Tally light screen: the pulse switch shows a filled disc when on.
- [ ] Low Power Mode on, screen dimmed: "Low battery" under the
      percentage.

**Sufficient Contrast** (Display & Text Size → Increase Contrast, then
Reduce Transparency on its own):

- [ ] Point the camera at a bright white wall. The pills, the tray and
      the glass buttons are dark and solid, with a light edge under
      Increase Contrast; the tray's mode line reads as near-white.

**Reduced Motion** (Accessibility → Motion → Reduce Motion):

- [ ] Give a tally status Pulse: the border holds steady.
- [ ] Open and close the tray, let the idle view engage and wake it,
      tap to focus: nothing slides or scales.

## The multitasking camera entitlement

Requested from Apple (form answers recorded below). The submitted build
does not depend on it: the camera stream stops when the app leaves the
screen (the app's one background mode, `screen-capture`, covers screen
mirroring on iOS 27 and later, not the camera). When granted: add the entitlement
to the app target in `project.yml` and update `docs/DEVELOPMENT.md`'s
backgrounding section, the site's FAQ and this note.

- App Name: LensLink Camera
- Bundle ID: `com.exaltedpixels.LensLinkCamera`
- Primary purpose video calls/conferencing: **No**
- Why: the app streams the camera to OBS as a production camera. An
  operator often needs another app briefly during a stream (a chat, a
  run sheet, a timer), and iOS stops capture the moment the app is not
  on screen, so today the stream ends when they leave. The entitlement
  would let capture continue while the operator is elsewhere, the way
  it already does beside another app on a supported iPad.
- Camera use: capture from the built-in cameras with full manual
  control, hardware encode with VideoToolbox, stream over LAN or USB to
  OBS. Nothing recorded, nothing leaves the local network, camera runs
  only after Start with the system indicator on.

## Before the first submission

- [ ] Privacy and support pages live on lenslink.cam (`site/pages/`).
- [ ] Screenshots uploaded for both device sizes.
- [ ] Demo video recorded and its link pasted into the review notes.
- [ ] App Privacy questionnaire answered (Data Not Collected).
- [ ] Age rating questionnaire answered (4+).
- [ ] Accessibility Nutrition Labels answered for iPhone and iPad, after
      the device checks above.
- [ ] The build chosen is a **stable** release, not a `-beta.N`.
- [x] After approval: switch the TestFlight links in the README, the
      site (download, setup) and the release-notes install table to the
      App Store link, and keep TestFlight as the beta channel.

The app is live: [LensLink Camera](https://apps.apple.com/app/lenslink-camera/id6790673163)
(app id `6790673163`). Every stable release still uploads to App Store
Connect and TestFlight automatically; putting it on the App Store is a
manual **Add for Review** of that build.
