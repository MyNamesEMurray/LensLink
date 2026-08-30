import SwiftUI
import UIKit

/// Battery level, charging state and Low Power Mode, published for the
/// Live screen's dim readout and the low-battery tally status.
///
/// Notification-driven, never polled: iOS posts a level change every 5%
/// (that is the granularity `UIDevice` offers — a percentage that moves in
/// steps of five is expected, not a bug) and a state change whenever the
/// cable comes and goes. A timer here would burn wakeups during exactly
/// the long unattended streams this readout exists for
/// (docs/PERFORMANCE.md: no extra threads or timers).
///
/// Monitoring is refcounted rather than left on for the app's life: it is
/// a device-wide flag, and only the Live screen has anything to show.
@MainActor
final class BatteryMonitor: ObservableObject {
    static let shared = BatteryMonitor()

    /// 0–100, or nil when iOS won't say (Simulator, or monitoring off).
    @Published private(set) var percent: Int?
    @Published private(set) var isCharging = false
    @Published private(set) var lowPowerMode = ProcessInfo.processInfo
        .isLowPowerModeEnabled

    /// Below this, the phone is "low" even without Low Power Mode — iOS
    /// offers its own prompt at the same 20%, so the two agree in the
    /// common case and this still fires for someone who declined it.
    private static let lowPercent = 20

    /// The condition the tally light and the readout's colour both key
    /// off. Charging clears it: a phone on a cable is not a problem to
    /// warn about, however empty it is right now.
    var isLow: Bool {
        guard !isCharging else { return false }
        return lowPowerMode || (percent.map { $0 <= Self.lowPercent } ?? false)
    }

    private var observers: [NSObjectProtocol] = []
    private var users = 0

    private init() {}

    /// Starts monitoring for one screen; balance with `release()`.
    func retain() {
        users += 1
        guard users == 1 else { return }
        UIDevice.current.isBatteryMonitoringEnabled = true
        read()
        let center = NotificationCenter.default
        for name: NSNotification.Name in [
            UIDevice.batteryLevelDidChangeNotification,
            UIDevice.batteryStateDidChangeNotification,
            .NSProcessInfoPowerStateDidChange,
        ] {
            observers.append(center.addObserver(
                forName: name, object: nil, queue: .main) { [weak self] _ in
                // The notifications are posted on the main queue, but
                // `self` is main-actor isolated and the closure isn't, so
                // hop explicitly rather than assert.
                Task { @MainActor [weak self] in self?.read() }
            })
        }
    }

    func release() {
        users = max(0, users - 1)
        guard users == 0 else { return }
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        UIDevice.current.isBatteryMonitoringEnabled = false
    }

    private func read() {
        let device = UIDevice.current
        // -1 means unknown; a percentage of "-100%" would be worse than
        // showing nothing at all.
        percent = device.batteryLevel < 0
            ? nil : Int((device.batteryLevel * 100).rounded())
        isCharging = device.batteryState == .charging
            || device.batteryState == .full
        lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    }
}
