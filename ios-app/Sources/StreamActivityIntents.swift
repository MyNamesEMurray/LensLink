#if canImport(AppIntents)
import AppIntents

/// The Live Activity's two buttons. `LiveActivityIntent` (iOS 17) runs
/// `perform` in the app's own process, which is how a tap on the Lock
/// Screen reaches the streamer without unlocking the phone.
///
/// Compiled into both the app and the widget extension: the widget
/// needs the types to draw `Button(intent:)`, the app needs them to
/// run. `LENSLINK_WIDGET` (set on the widget target in project.yml)
/// keeps the bodies — which reach into `Streamer` — out of the target
/// that has no streamer.
@available(iOS 17.0, *)
struct PauseStreamActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause or Resume Stream"
    static var description = IntentDescription(
        "Holds the LensLink stream, or lets it run again.")

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !LENSLINK_WIDGET
        let streamer = Streamer.shared
        streamer.setPaused(!streamer.isPaused, reason: .user)
        #endif
        return .result()
    }
}

@available(iOS 17.0, *)
struct StopStreamActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop Stream"
    static var description = IntentDescription(
        "Stops the LensLink camera stream.")

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !LENSLINK_WIDGET
        Streamer.shared.stop()
        #endif
        return .result()
    }
}
#endif
