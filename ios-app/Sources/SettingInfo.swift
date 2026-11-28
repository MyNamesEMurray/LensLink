import SwiftUI

/// The one-paragraph description of a setting, shared by its Documentation
/// page and the setting's own info button, so the two never drift.
enum SettingInfo {
    static let bitrate = LocalizedStringKey(
        "**Bitrate**, in the Camera sheet. **Stable** streams at a bitrate that is safe on ordinary Wi-Fi and only backs off from it. **Maximum** starts higher and keeps probing upward while the connection stays clean — up to about six times the Stable rate over USB, four over Wi-Fi — backing off the moment frames queue or drop and settling just under whatever the link carries. It also switches the encoder to quality-first settings and, unless system video effects are allowed, streams from the full sensor readout rather than the binned format. More data and more heat; watch the Stats line the first time.")
    static let greenScreen = LocalizedStringKey(
        "**Green screen** keeps you in the picture and paints everything else solid green before the video leaves the phone — turning it on sets Color to Standard. The **LensLink Camera** source in OBS adds a ready-tuned filter that keys the green out; it's added once, so deleting or re-tuning it in OBS sticks.")
    static let stabilization = LocalizedStringKey(
        "**Stabilization** steadies a handheld or moving shot. It's off by default because the phone holds frames back to smooth them, which delays the stream. Standard adds a little. Cinematic adds a lot, often more than half a second, and crops the picture a little more, so save it for shots that don't need to line up with a game or other sources. It stays off in formats that don't offer the mode you pick, and while depth assist runs.")
    static let antiFlicker = LocalizedStringKey(
        "**Anti-flicker**, in the Camera sheet, rounds the automatic shutter to a whole number of the pulses that mains-powered lights give off (twice the mains frequency), so they don't flicker or band. It moves the slowest shutter auto exposure may use (natural motion blur's 180° limit) to the nearest of 1/120, 1/60, 1/40, 1/30 at 60 Hz, or 1/100, 1/50, 1/33 at 50 Hz: 1/120 at 120 fps and 60 Hz. A frame rate above twice the mains (120 fps at 50 Hz, 240 fps) leaves no safe value, so the 180° value stays. A shutter you set by hand is never rounded. **Auto** takes 50 or 60 Hz from your Region setting; in east Japan pick 50 Hz.")
    static let reframe = LocalizedStringKey(
        "**High-quality reframe** captures at the next size up (1080p for a 720p stream, 4K for 1080p) and takes the web panel's Reframe window from that, so zoom keeps real detail instead of stretching pixels. It uses more power and heat, turns green screen off, and does nothing at 4K.")
    static let remoteStart = LocalizedStringKey(
        "**Arm Remote Start**, under Start Camera, lets OBS start and stop the camera for you. Until you tap it OBS can see the phone but can't start the camera, so opening the app never starts a stream by itself. Arming lasts until you tap Disarm, stop a stream on the phone, or leave the app; the phone stays awake while it waits. **Arm remote start on open** arms it every time the app opens, for a phone that's mounted out of reach. Siri: \"Start streaming with LensLink.\"")
    static let idleView = LocalizedStringKey(
        "**Idle view** is what the Live screen becomes 10 seconds after you last touch it, for a phone that's mounted and out of reach. **Standard** leaves the controls up. **Clean feed** hides everything but the picture — turn Stats on (status pill) before you stop touching it to keep the health readout. **Dim screen** blanks the screen and drops the brightness to save battery, and is the only one that also dims remote-start standby, a minute in. Any tap brings the controls back.")
    static let remember = LocalizedStringKey(
        "**Remember camera settings** keeps each camera's exposure, white balance, zoom and focus from one stream to the next — a shot dialled in once stays dialled in, per lens. Turn it off and every camera starts on auto, and what was stored is forgotten.")
    static let videoEffects = LocalizedStringKey(
        "**Allow system video effects** is experimental: it lets iOS lower the frame rate on its own, which the Control Center video effects (Portrait, Studio Light) may require. Takes effect when the camera next starts.")
    static let proInterface = LocalizedStringKey(
        "**Pro interface** replaces the Live screen with a layout for camera operators: every value in one strip, a dial for the one you tap, the link's bitrate and frame rate, the phone mic's level and framing guides.")

    // The ⓘ alerts: what the setting does, in a sentence or two. The
    // paragraphs above stay the Documentation pages' fuller text.
    static let bitrateTip = LocalizedStringKey(
        "**Stable**: a bitrate safe on ordinary Wi-Fi. **Maximum**: climbs as high as the link allows, up to 6× Stable over USB and 4× over Wi-Fi. More heat.")
    static let greenScreenTip = LocalizedStringKey(
        "Paints everything except you solid green on the phone. Sets Color to Standard. The LensLink Camera source in OBS adds a filter that keys the green out.")
    static let stabilizationTip = LocalizedStringKey(
        "Steadies moving shots but delays the stream. Standard adds a little delay. Cinematic adds often over half a second and crops more.")
    static let antiFlickerTip = LocalizedStringKey(
        "Rounds the automatic shutter so lights on mains power don't flicker. Auto picks 50 or 60 Hz from your Region.")
    static let irisTip = LocalizedStringKey(
        "Lens opening. A lower f-number lets in more light and blurs the background more. A higher one keeps more in focus.")
    static let reframeTip = LocalizedStringKey(
        "Captures one size up (4K for a 1080p stream) so Reframe zoom keeps real detail. Uses more power and heat and turns green screen off. Not available at 4K.")
    static let remoteStartTip = LocalizedStringKey(
        "Lets OBS start and stop the camera. Stays armed until you disarm, stop a stream on the phone, or leave the app. The phone stays awake while armed.")
    static let idleViewTip = LocalizedStringKey(
        "What the Live screen shows 10 seconds after your last touch. **Standard**: controls stay. **Clean feed**: the picture only. **Dim screen**: the screen goes dark to save battery. Tap to bring the controls back.")
    static let rememberTip = LocalizedStringKey(
        "Keeps each lens's exposure, white balance, zoom and focus from one stream to the next. Off: every camera starts on auto.")
    static let videoEffectsTip = LocalizedStringKey(
        "Lets iOS lower the frame rate, which Control Center video effects (Portrait, Studio Light) may need. Applies the next time the camera starts.")
    static let proInterfaceTip = LocalizedStringKey(
        "Replaces the Live screen with every camera value in one strip, the link's bitrate and frame rate, the mic level and framing guides.")
}

/// A small ⓘ beside a setting: tap for its description in an alert.
/// Borderless, so a tap inside a Form row reaches it and not the row.
struct InfoButton: View {
    let title: String
    let text: LocalizedStringKey
    @State private var shown = false

    var body: some View {
        Button {
            shown = true
        } label: {
            Image(systemName: "info.circle")
                .foregroundColor(.secondary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(L("About %@", title))
        .alert(title, isPresented: $shown) {
            Button("Done") {}
        } message: {
            Text(text)
        }
    }
}
