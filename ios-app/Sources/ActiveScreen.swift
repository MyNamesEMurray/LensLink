import UIKit

/// The screen — and the scene — this app's UI is actually on.
///
/// `UIScreen.main` was deprecated in iOS 26 and under iOS 27 it is
/// actively the wrong answer. An app built with the 27 SDK gets freely
/// resizable iPad windows and can be hosted by iPhone Mirroring, where a
/// scene is connected to a `UIScreen` that isn't `UIScreen.main`.
/// Brightness written to a screen the UI isn't on does nothing at all,
/// which would leave the dim views stuck at full brightness with no error
/// anywhere. Ask the app's own scene which screen it is on instead.
///
/// `UIScreen.isCaptured` is deprecated in iOS 27 in its turn, replaced by
/// the `sceneCaptureState` trait — the same question asked per scene
/// rather than per screen. `UIScreen.capturedDidChangeNotification`, which
/// is how we hear that it changed, is *not* deprecated, so it stays the
/// trigger and the trait is only the read.
enum ActiveScreen {
    /// The foreground window scene, falling back to any connected one.
    /// Nil while the app has no scene at all (backgrounded, or still
    /// launching) — every caller here has nothing to do in that state.
    static var scene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first
    }

    /// The screen the UI is on, or nil when there is no scene.
    static var screen: UIScreen? { scene?.screen }

    /// Screen brightness. Reading with no scene reports full brightness:
    /// the value is only ever kept as the level to restore later, and
    /// restoring to full beats restoring to black.
    static var brightness: CGFloat {
        get { screen?.brightness ?? 1 }
        set { screen?.brightness = newValue }
    }

    /// Whether the UI is being recorded, mirrored, or sent over AirPlay.
    static var isCaptured: Bool {
        if #available(iOS 17.0, *) {
            guard let scene else { return false }
            return scene.traitCollection.sceneCaptureState == .active
        }
        return screen?.isCaptured ?? false
    }
}
