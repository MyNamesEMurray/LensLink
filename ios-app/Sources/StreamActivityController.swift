#if canImport(ActivityKit)
import ActivityKit
import Combine
import Foundation

/// Starts, updates and ends the stream's Live Activity by watching the
/// streamer: one per app, attached once from the scene. The activity
/// follows `isStreaming` (start/end) and re-renders on any published
/// change that alters its content state — status word, tally, pause,
/// the computer's name once `identify` arrives.
///
/// iOS 16.1 API on purpose (`request(attributes:contentState:)`,
/// `update(using:)`, `end(using:dismissalPolicy:)`): 16.2 wraps the
/// same calls in `ActivityContent` and deprecates these, but the floor
/// is what matters and a deprecation warning costs nothing. Everything
/// here is behind `#available(iOS 16.1, *)` and ActivityKit is
/// weak-linked (project.yml), so iOS 15 never sees any of it.
@available(iOS 16.1, *)
@MainActor
final class StreamActivityController {
    static let shared = StreamActivityController()

    private var activity: Activity<StreamActivityAttributes>?
    private var startedAt = Date()
    private var cancellable: AnyCancellable?

    private init() {}

    /// Idempotent. Ends any activity left over from a previous process
    /// (a stream the app died in the middle of would otherwise sit on
    /// the Lock Screen for hours), then follows the streamer.
    func attach(_ streamer: Streamer) {
        guard cancellable == nil else { return }
        for stale in Activity<StreamActivityAttributes>.activities {
            Task { await stale.end(dismissalPolicy: .immediate) }
        }
        // objectWillChange fires *before* the change lands; the debounce
        // reads the settled state and also folds a burst of updates
        // (start sets half a dozen properties) into one request.
        cancellable = streamer.objectWillChange
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .sink { [weak self, weak streamer] _ in
                Task { @MainActor [weak self, weak streamer] in
                    guard let self, let streamer else { return }
                    self.sync(streamer)
                }
            }
        sync(streamer)
    }

    private func sync(_ streamer: Streamer) {
        if streamer.isStreaming {
            if activity == nil {
                startedAt = Date()
            }
            let state = contentState(streamer)
            if let activity {
                guard activity.contentState != state else { return }
                Task { await activity.update(using: state) }
            } else {
                guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
                activity = try? Activity.request(
                    attributes: StreamActivityAttributes(),
                    contentState: state,
                    pushType: nil)
            }
        } else if let activity {
            self.activity = nil
            let state = contentState(streamer)
            // Immediate: a "Not connected" card lingering on the Lock
            // Screen after Stop would read as a stream that is still on.
            Task { await activity.end(using: state, dismissalPolicy: .immediate) }
        }
    }

    private func contentState(_ streamer: Streamer)
        -> StreamActivityAttributes.ContentState {
        let transport: String
        switch streamer.obsTransport {
        case "usb": transport = "USB"
        case "lan": transport = "Wi-Fi"
        default: transport = ""
        }
        return StreamActivityAttributes.ContentState(
            statusWord: streamer.status.displayName,
            onAir: streamer.tally == .live,
            paused: streamer.isPaused,
            startedAt: startedAt,
            host: streamer.obsHost ?? "OBS",
            format: "\(streamer.resolution.rawValue) · \(streamer.fps) fps · "
                + streamer.codec.label,
            transport: transport)
    }
}
#endif
