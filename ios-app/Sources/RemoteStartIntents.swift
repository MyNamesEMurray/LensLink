#if canImport(AppIntents)
import AppIntents

/// Siri / Shortcuts entry points for remote start (iOS 16+; iOS 15 can use
/// the lenslink://start URL in a Shortcuts "Open URL" action instead).
///
/// The camera can only capture while the app is foreground, so the start
/// intent opens the app — "Hey Siri, start streaming with LensLink" wakes
/// the phone straight into a running stream, no touch needed.
@available(iOS 16.0, *)
struct StartCameraStreamIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Camera Stream"
    static var description = IntentDescription(
        "Opens LensLink and starts streaming the camera to OBS.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        await Streamer.shared.start()
        return .result()
    }
}

@available(iOS 16.0, *)
struct StopCameraStreamIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Camera Stream"
    static var description = IntentDescription(
        "Stops the LensLink camera stream.")

    @MainActor
    func perform() async throws -> some IntentResult {
        Streamer.shared.stop()
        return .result()
    }
}

/// Pre-registered Siri phrases — no Shortcuts setup required.
/// (The shortTitle/systemImageName initializer is 16.4+; on 16.0–16.3 the
/// intents are still available as actions in the Shortcuts app.)
@available(iOS 16.4, *)
struct LensLinkShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartCameraStreamIntent(),
            phrases: [
                "Start streaming with \(.applicationName)",
                "Start the \(.applicationName) camera",
                "Start \(.applicationName)",
            ],
            shortTitle: "Start Camera",
            systemImageName: "video.fill")
        AppShortcut(
            intent: StopCameraStreamIntent(),
            phrases: [
                "Stop streaming with \(.applicationName)",
                "Stop the \(.applicationName) camera",
            ],
            shortTitle: "Stop Camera",
            systemImageName: "stop.fill")
    }
}
#endif
