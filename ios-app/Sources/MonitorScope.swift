import AVFoundation
import CoreImage
import ImageIO
import SwiftUI

/// The Pro interface's monitoring tools: histogram, zebra stripes, focus
/// peaking, false colour and the phone-mic meter. Everything here is drawn
/// on the phone's screen only, never into the stream.
///
/// Frames come from the capture callback the encoder already uses. At most
/// one frame is being analysed at a time, about ten a second, on a copy
/// scaled down to 360 pixels wide; a frame that arrives while the last one
/// is still being worked on is skipped, never queued (docs/PERFORMANCE.md).
/// With every tool off, `note` costs one lock read per frame.
final class MonitorScope: ObservableObject, @unchecked Sendable {
    struct Tools: Equatable {
        /// Zebra threshold, 0.7 to 1.0 of full scale; nil while zebra is off.
        var zebraLevel: Double?
        var peaking = false
        var falseColor = false
        /// Histogram and mic meter: on while the Pro interface is showing.
        var metering = false
        /// How the delivered (sensor-landscape) buffer is turned to match
        /// the on-screen preview.
        var orientation: CGImagePropertyOrientation = .up

        var drawsOverlay: Bool { zebraLevel != nil || peaking || falseColor }
        var any: Bool { drawsOverlay || metering }
    }

    /// The zebra, peaking and false-colour layer, already turned to the
    /// preview's orientation; nil while none of them is on.
    @Published private(set) var overlay: CGImage?
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
    /// No colour management: the scopes read the signal as encoded, the
    /// way a camera's zebra and false colour do.
    private let context = CIContext(options: [.workingColorSpace: NSNull(),
                                              .outputColorSpace: NSNull(),
                                              .cacheIntermediates: false])
    private static let width: CGFloat = 360
    private static let bins = 64

    func setTools(_ new: Tools) {
        tools.value = new
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !new.drawsOverlay { self.overlay = nil }
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
        let current = tools.value
        guard current.any else { return }
        let now = CACurrentMediaTime()
        guard now - lastFrame.value >= 0.1, !busy.value,
              let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame.value = now
        busy.value = true
        queue.async { [self] in
            analyse(pixels, current)
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

    private func analyse(_ pixels: CVPixelBuffer, _ tools: Tools) {
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
        let extent = luma.extent

        var bins: [Float] = []
        if tools.metering {
            bins = histogram(of: luma, extent: extent)
        }

        var image: CGImage?
        if tools.drawsOverlay {
            var layer = tools.falseColor
                ? luma.applyingFilter("CIColorMap", parameters: [
                    "inputGradientImage": Self.falseColorPalette,
                ]).cropped(to: extent)
                : CIImage(color: .clear).cropped(to: extent)
            if tools.peaking {
                let edges = luma
                    .applyingFilter("CIEdges", parameters: ["inputIntensity": 6])
                    .applyingFilter("CIColorThreshold", parameters: ["inputThreshold": 0.3])
                    .cropped(to: extent)
                let tint = CIImage(color: CIColor(red: 0.39, green: 0.82, blue: 1))
                    .cropped(to: extent)
                layer = tint.applyingFilter("CIBlendWithMask", parameters: [
                    kCIInputBackgroundImageKey: layer,
                    kCIInputMaskImageKey: edges,
                ])
            }
            if let level = tools.zebraLevel {
                let over = luma
                    .applyingFilter("CIColorThreshold", parameters: ["inputThreshold": level])
                layer = Self.stripes.cropped(to: extent)
                    .applyingFilter("CIBlendWithMask", parameters: [
                    kCIInputBackgroundImageKey: layer,
                    kCIInputMaskImageKey: over,
                ])
            }
            let turned = layer.oriented(tools.orientation)
            image = context.createCGImage(turned, from: turned.extent)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if tools.metering { self.histogram = bins }
            if tools.drawsOverlay { self.overlay = image }
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

    /// Black and white diagonal stripes, eight pixels apart: readable over
    /// any highlight, where white stripes alone would vanish.
    private static let stripes: CIImage = {
        let generator = CIFilter(name: "CIStripesGenerator", parameters: [
            "inputColor0": CIColor.white,
            "inputColor1": CIColor.black,
            "inputWidth": 4,
            "inputSharpness": 1,
        ])
        return (generator?.outputImage ?? CIImage(color: .white))
            .transformed(by: CGAffineTransform(rotationAngle: .pi / 4))
    }()

    /// Luma to colour: grey everywhere except the bands a camera operator
    /// exposes by. Purple crushed, blue two stops under, green middle
    /// grey, pink skin, yellow bright highlights, red clipped.
    static let falseColorPalette: CIImage = {
        let size = 256
        var pixels = [UInt8](repeating: 255, count: size * 4)
        for i in 0..<size {
            let v = Double(i) / Double(size - 1)
            let grey = UInt8(i)
            var rgb: (UInt8, UInt8, UInt8) = (grey, grey, grey)
            switch v {
            case ..<0.03: rgb = (94, 47, 134)
            case 0.08..<0.14: rgb = (47, 111, 208)
            case 0.40..<0.48: rgb = (58, 154, 72)
            case 0.52..<0.60: rgb = (212, 106, 140)
            case 0.90..<0.97: rgb = (232, 192, 42)
            case 0.97...: rgb = (229, 55, 43)
            default: break
            }
            pixels[i * 4] = rgb.0
            pixels[i * 4 + 1] = rgb.1
            pixels[i * 4 + 2] = rgb.2
        }
        return CIImage(bitmapData: Data(pixels), bytesPerRow: size * 4,
                       size: CGSize(width: size, height: 1),
                       format: .RGBA8, colorSpace: nil)
    }()

    /// The turn that puts the sensor-landscape buffer the way the preview
    /// shows it. The preview mirrors the front camera after rotating, so
    /// a front lens turns the other way in portrait.
    static func orientation(for interface: UIInterfaceOrientation,
                            front: Bool) -> CGImagePropertyOrientation {
        switch interface {
        case .portrait: return front ? .left : .right
        case .portraitUpsideDown: return front ? .right : .left
        case .landscapeLeft: return .down
        default: return .up
        }
    }
}
