import SwiftUI
import UIKit

final class AssistiveTech: ObservableObject {
    static let shared = AssistiveTech()

    @Published private(set) var suspendsIdle = AssistiveTech.running

    private var observers: [NSObjectProtocol] = []

    private init() {
        let center = NotificationCenter.default
        for name: NSNotification.Name in [
            UIAccessibility.voiceOverStatusDidChangeNotification,
            UIAccessibility.switchControlStatusDidChangeNotification,
        ] {
            observers.append(center.addObserver(
                forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            })
        }
    }

    private func refresh() {
        let running = Self.running
        if running != suspendsIdle {
            suspendsIdle = running
        }
    }

    private static var running: Bool {
        UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning
    }

    @MainActor
    static func announce(_ text: String) {
        guard UIAccessibility.isVoiceOverRunning, !text.isEmpty else { return }
        let queued = NSAttributedString(
            string: text,
            attributes: [.accessibilitySpeechQueueAnnouncement: true])
        UIAccessibility.post(notification: .announcement, argument: queued)
    }

    @MainActor
    static func haptic(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}
