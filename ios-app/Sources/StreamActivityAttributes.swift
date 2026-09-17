#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// The stream as a Live Activity (Lock Screen card + Dynamic Island).
/// Compiled into both the app (which starts, updates and ends it —
/// `StreamActivityController`) and the widget extension (which draws
/// it — `WidgetExtension/LensLinkWidgets.swift`); the two must agree
/// byte for byte, which is why this is one file in two targets rather
/// than two copies.
///
/// Everything lives in the content state, attributes included in
/// spirit: the computer's name arrives a moment *after* the stream
/// starts (the plugin's `identify`), and attributes are fixed at
/// request time, so a name in the attributes would be "OBS" forever.
@available(iOS 16.1, *)
struct StreamActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// The status word every surface shares (`Status.displayName`).
        var statusWord: String
        /// The tally: on air (program) is the state the card exists to
        /// show, so it gets its own flag rather than a colour name.
        var onAir: Bool
        var paused: Bool
        /// When the stream began; the card's elapsed timer counts from
        /// it and the system keeps it ticking without any updates.
        var startedAt: Date
        /// "Studio-Mac" once the plugin has said so, "OBS" until then.
        var host: String
        /// "4K · 60 fps · HEVC".
        var format: String
        /// "USB", "Wi-Fi", or empty before the plugin has said.
        var transport: String
    }

    /// Nothing fixed: see the type comment.
    var name = "LensLink"
}
#endif
