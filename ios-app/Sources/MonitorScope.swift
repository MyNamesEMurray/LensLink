import QuartzCore
import SwiftUI

/// The Pro interface's phone-mic meter. Drawn on the phone's screen
/// only, never into the stream. With metering off, `noteAudio` costs one
/// lock read per buffer.
final class MonitorScope: ObservableObject, @unchecked Sendable {
    struct Tools: Equatable {
        /// Mic meter: on while the Pro interface is showing.
        var metering = false
    }

    /// Peak level of the phone mic over the last tenth of a second, in
    /// dBFS; nil while the mic isn't being captured.
    @Published private(set) var micLevel: Float?

    private let tools = Locked(Tools())
    private let audioPeak = Locked<(peak: Int, since: CFTimeInterval)>((0, 0))

    func setTools(_ new: Tools) {
        tools.value = new
        DispatchQueue.main.async { [weak self] in
            if !new.metering { self?.micLevel = nil }
        }
    }

    func updateTools(_ change: (inout Tools) -> Void) {
        var next = tools.value
        change(&next)
        if next != tools.value { setTools(next) }
    }
    /// Audio thread: 16-bit PCM from the phone mic.
    func noteAudio(_ pcm: Data) {
        guard tools.value.metering, PerfProbe.shared.micMeterOn.value else { return }
        var peak = 0
        pcm.withUnsafeBytes { raw in
            for sample in raw.bindMemory(to: Int16.self) {
                peak = max(peak, abs(Int(sample)))
            }
        }
        let now = CACurrentMediaTime()
        var window = audioPeak.value
        window.peak = max(window.peak, peak)
        guard now - window.since >= 0.1 else {
            audioPeak.value = window
            return
        }
        audioPeak.value = (0, now)
        let dbfs = window.peak > 0
            ? 20 * log10(Float(window.peak) / Float(Int16.max)) : -90
        DispatchQueue.main.async { [weak self] in self?.micLevel = dbfs }
    }

    func micStopped() {
        DispatchQueue.main.async { [weak self] in self?.micLevel = nil }
    }
}
