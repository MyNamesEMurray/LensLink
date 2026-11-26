import AVFoundation
import CoreImage
import SwiftUI

/// The Pro interface's histogram and phone-mic meter. Drawn on the
/// phone's screen only, never into the stream.
///
/// Frames come from the capture callback the encoder already uses. At most
/// one frame is being analysed at a time, about ten a second, on a copy
/// scaled down to 360 pixels wide; a frame that arrives while the last one
/// is still being worked on is skipped, never queued (docs/PERFORMANCE.md).
/// With metering off, `note` costs one lock read per frame.
final class MonitorScope: ObservableObject, @unchecked Sendable {
    struct Tools: Equatable {
        /// Histogram and mic meter: on while the Pro interface is showing.
        var metering = false
    }

    /// 64 luma bins, 0 to 1, tallest bin = 1. Empty while metering is off.
    @Published private(set) var histogram: [Float] = []
    /// Peak level of the phone mic over the last tenth of a second, in
    /// dBFS; nil while the mic isn't being captured.
    @Published private(set) var micLevel: Float?

    private let tools = Locked(Tools())
    private let busy = Locked(false)
    private let lastFrame = Locked<CFTimeInterval>(0)
    private let audioPeak = Locked<(peak: Int, since: CFTimeInterval)>((0, 0))
    private let queue = DispatchQueue(label: "cam.lenslink.scope", qos: .utility)
    /// No colour management: the histogram reads the signal as encoded.
    private let context = CIContext(options: [.workingColorSpace: NSNull(),
                                              .outputColorSpace: NSNull(),
                                              .cacheIntermediates: false])
    private static let width: CGFloat = 360
    private static let bins = 64

    func setTools(_ new: Tools) {
        tools.value = new
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !new.metering {
                self.histogram = []
                self.micLevel = nil
            }
        }
    }

    func updateTools(_ change: (inout Tools) -> Void) {
        var next = tools.value
        change(&next)
        if next != tools.value { setTools(next) }
    }

    /// Capture queue, once per frame.
    func note(_ sampleBuffer: CMSampleBuffer) {
        guard tools.value.metering else { return }
        let now = CACurrentMediaTime()
        guard now - lastFrame.value >= 0.1, !busy.value,
              let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame.value = now
        busy.value = true
        queue.async { [self] in
            analyse(pixels)
            busy.value = false
        }
    }

    /// Audio thread: 16-bit PCM from the phone mic.
    func noteAudio(_ pcm: Data) {
        guard tools.value.metering else { return }
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

    private func analyse(_ pixels: CVPixelBuffer) {
        let full = CIImage(cvPixelBuffer: pixels)
        guard full.extent.width > 0 else { return }
        let scale = Self.width / full.extent.width
        let small = full.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let weights = CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0)
        let luma = small.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": weights, "inputGVector": weights,
            "inputBVector": weights,
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0),
        ])
        let bins = histogram(of: luma, extent: luma.extent)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.tools.value.metering else { return }
            self.histogram = bins
        }
    }

    private func histogram(of luma: CIImage, extent: CGRect) -> [Float] {
        let counted = luma.applyingFilter("CIAreaHistogram", parameters: [
            kCIInputExtentKey: CIVector(cgRect: extent),
            "inputCount": Self.bins,
            "inputScale": 1,
        ])
        var raw = [Float](repeating: 0, count: Self.bins * 4)
        raw.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            context.render(counted, toBitmap: base,
                           rowBytes: Self.bins * 4 * MemoryLayout<Float>.size,
                           bounds: CGRect(x: 0, y: 0, width: Self.bins, height: 1),
                           format: .RGBAf, colorSpace: nil)
        }
        let bins = stride(from: 0, to: raw.count, by: 4).map { raw[$0] }
        let tallest = bins.max() ?? 0
        return tallest > 0 ? bins.map { $0 / tallest } : bins
    }
}
