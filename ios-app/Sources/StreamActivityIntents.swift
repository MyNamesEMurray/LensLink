#if canImport(AppIntents)
import AppIntents

/// The Live Activity's one button. `LiveActivityIntent` (iOS 17) runs
/// `perform` in the app's own process, which is how a tap on the Lock
/// Screen reaches the streamer without unlocking the phone. Stop is the
/// only verb that makes sense there: if you are looking at the Lock
/// Screen, the camera is already held or gone, and "resume" would
/// promise a picture iOS won't give until the app is back on screen.
///
/// Compiled into both the app and the widget extension: the widget
/// needs the type to draw `Button(intent:)`, the app needs it to run.
/// `LENSLINK_WIDGET` (set on the widget target in project.yml) keeps the
/// body — which reaches into `Streamer` — out of the target that has no
/// streamer.
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
