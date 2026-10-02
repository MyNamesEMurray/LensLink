import UIKit

/// The window scene, and through it the screen, this app's UI is on.
///
/// `UIScreen.main` is deprecated (iOS 16) and warns under newer SDKs.
/// Asking the app's own scene gives the same screen on a single-screen
/// iPhone or iPad, and follows the UI when a scene can sit elsewhere.
/// Only application scenes count, so an external-display scene is never
/// the one dimmed.
enum ActiveScreen {
    /// The foreground application scene, falling back to any connected
    /// one. Nil while the app has no scene (still launching).
    static var scene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.session.role == .windowApplication }
        return scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first { $0.activationState == .foregroundInactive }
            ?? scenes.first
    }

    /// The screen the UI is on, or nil when there is no scene.
    static var screen: UIScreen? { scene?.screen }

    /// Safe-area insets of the scene's key window, or zero when it has
    /// none yet. Read live: rotation and iPad window resizing change them.
    static var keyWindowSafeAreaInsets: UIEdgeInsets {
        guard let scene else { return .zero }
        let window = scene.keyWindow ?? scene.windows.first
        return window?.safeAreaInsets ?? .zero
    }
}

/// A brightness level taken from one screen and owed back to that same
/// screen, so the restore can't land on a different one than the dim did.
struct LoweredBrightness {
    private weak var screen: UIScreen?
    private let previous: CGFloat

    /// Drops the UI's screen to `level`, remembering what it was. Nil
    /// when there is no screen to dim.
    static func lower(to level: CGFloat) -> LoweredBrightness? {
        guard let screen = ActiveScreen.screen else { return nil }
        let lowered = LoweredBrightness(screen: screen,
                                        previous: screen.brightness)
        screen.brightness = level
        return lowered
    }

    func restore() {
        screen?.brightness = previous
    }
}
