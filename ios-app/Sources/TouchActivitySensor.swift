import SwiftUI
import UIKit

/// Reports every touch-down in the window without ever competing for it.
///
/// The standby dim's fuse must reset on any interaction — scrolling and
/// reading included — but doing that with a SwiftUI
/// `DragGesture(minimumDistance: 0)` on the settings form claimed every
/// first touch: single-tap stopped opening the menu pickers on some iOS
/// releases, and stopped reaching the UIKit broadcast picker overlay on
/// all of them (#96, #97, #99 — the reporters' two-finger workaround was
/// the second touch slipping past the drag, which only tracks the first).
///
/// This sensor instead attaches a UIKit recognizer to the *window* that
/// fires its callback in `touchesBegan` and immediately fails itself, so
/// it leaves gesture arbitration before any other recognizer or view can
/// be affected by it. Window level is load-bearing: the sensor lives in
/// a `.background`, where hit-testing would never hand it the form's own
/// touches.
struct TouchActivitySensor: UIViewRepresentable {
    var onTouch: () -> Void

    func makeUIView(context: Context) -> SensorView {
        let view = SensorView()
        view.recognizer.onTouchDown = onTouch
        return view
    }

    func updateUIView(_ view: SensorView, context: Context) {
        view.recognizer.onTouchDown = onTouch
    }

    /// Follows its window: attaches the recognizer when it lands in one,
    /// detaches when the hosting view leaves (so a dismissed screen never
    /// leaks a recognizer on the window).
    final class SensorView: UIView {
        let recognizer = TouchDownReporter()

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let attached = recognizer.view, attached !== window {
                attached.removeGestureRecognizer(recognizer)
            }
            if let window = window, recognizer.view == nil {
                window.addGestureRecognizer(recognizer)
            }
        }
    }

    /// Fires the callback on touch-down, then instantly bows out
    /// (`.failed`): it can never win, delay, or cancel another
    /// recognizer, and it never withholds touches from UIKit views. The
    /// three flags are belt and braces — a recognizer that fails in
    /// `touchesBegan` never uses them, but nobody should have to
    /// re-derive that while debugging the next touch issue. One
    /// consequence to know: a touch that never lifts (a single continuous
    /// minutes-long drag) reports only once, at its start — acceptable
    /// against a 60 s fuse.
    final class TouchDownReporter: UIGestureRecognizer {
        var onTouchDown: () -> Void = {}

        init() {
            super.init(target: nil, action: nil)
            cancelsTouchesInView = false
            delaysTouchesBegan = false
            delaysTouchesEnded = false
        }

        override func touchesBegan(_ touches: Set<UITouch>,
                                   with event: UIEvent) {
            onTouchDown()
            state = .failed
        }
    }
}
