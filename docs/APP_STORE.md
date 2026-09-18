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
> Screen** source in OBS. Test it the same way with that source type.
>
> **Background modes.** `audio`: the app captures the microphone while
> streaming when the user turns on "Send phone mic to OBS" (a wireless
> mic) or "Auto lip-sync reference" (a timing signal the plugin uses to
> align the user's own microphone; it is never heard). `voip`: this is
> declared for one feature, "Keep streaming in the background" (Options,
> on by default). When the user leaves the app mid-stream, the live
> picture moves into a Picture in Picture window so the camera keeps
> running; iOS grants that only to apps declaring voip or holding the
> multitasking-camera-access entitlement. The app is not a calling app;
> the feature exists because LensLink's output typically feeds a video
> call through OBS's virtual camera. We have requested the
> multitasking-camera-access entitlement and will drop the voip
> declaration the moment it is granted. Streaming only ever runs after
> the user taps Start, the system camera indicator is on throughout, and
> it stops on Stop, on lock, or from the computer.
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
> - Keep streaming while you switch apps
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

1. Home: the computer card naming the Mac, "OBS connected — ready",
   Camera / Format / Green screen rows.
2. Live, glance layer: the picture, status pill, Pause, Stop, lens
   buttons, tally border on air.
3. Live, adjust tray open on Exposure.
4. Format sheet: Quality and Color.
5. OBS on the Mac with the LensLink Camera source live (a Mac
   screenshot cropped to the store's iPhone frame is not allowed;
   photograph the setup, or skip this one).
6. Options.

## App Privacy questionnaire

**Data Not Collected.** The app makes no network requests except to
the user's own OBS on the local network; the only outbound links are to
GitHub (bug reports, source) and open in Safari. No analytics, no
crash reporting SDK, no identifiers.

## Export compliance

Already answered in the build: `ITSAppUsesNonExemptEncryption = false`
(plain TCP on the local network, no custom cryptography).

## The multitasking camera entitlement

Requested from Apple (form answers recorded below). Until granted, the
app ships with `voip` in `UIBackgroundModes` and the review note above
explains why. When granted: add the entitlement to the app target in
`project.yml`, remove `voip`, update `docs/DEVELOPMENT.md`'s background
streaming section and this note.

- App Name: LensLink Camera
- Bundle ID: `com.exaltedpixels.LensLinkCamera`
- Primary purpose video calls/conferencing: **No**
- Why: the app streams the camera to OBS as a production camera; the
  operator leaves the app briefly during a stream, and iOS stops capture
  the moment it is not on screen. Today the app works around that with
  a Picture in Picture window, which iOS allows only under `voip` — a
  mode that does not describe the app. The entitlement is the correct
  mechanism and lets the declaration go.
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
- [ ] The build chosen is a **stable** release, not a `-beta.N`.
- [ ] After approval: switch the TestFlight links in the README, the
      site (download, setup) and the release-notes install table to the
      App Store link, and set `Release-Skip`-free stable releases to
      keep TestFlight as the beta channel.
