import Foundation
import AVFoundation
import VideoToolbox

final class ReframeCell: @unchecked Sendable {
    struct Window: Equatable {
        var zoom = 1.0
        var x = 0.5
        var y = 0.5
        var isActive: Bool { zoom > 1.0001 }
    }

    static let maxZoom = 4.0

    private let lock = NSLock()
    private var stored = Window()

    var window: Window {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set {
            let zoom = min(max(newValue.zoom, 1), Self.maxZoom)
            let half = 0.5 / zoom
            lock.lock()
            stored = Window(zoom: zoom,
                            x: min(max(newValue.x, half), 1 - half),
                            y: min(max(newValue.y, half), 1 - half))
            lock.unlock()
        }
    }
}

@available(iOS 16.0, *)
final class FrameReframer {
    private let session: VTPixelTransferSession
    private var pool: CVPixelBufferPool?
    private var poolKey = ""
    private var cachedFormatDescription: CMVideoFormatDescription?
    private var loggedStages = Set<String>()

    private let outputWidth: Int
    private let outputHeight: Int

    init?(width: Int, height: Int) {
        outputWidth = width
        outputHeight = height
        var created: VTPixelTransferSession?
        guard VTPixelTransferSessionCreate(allocator: kCFAllocatorDefault,
                                           pixelTransferSessionOut: &created) == noErr,
              let created else { return nil }
        VTSessionSetProperty(created,
                             key: kVTPixelTransferPropertyKey_ScalingMode,
                             value: kVTScalingMode_CropSourceToCleanAperture)
        session = created
    }

    deinit { VTPixelTransferSessionInvalidate(session) }

    static func apply(_ reframer: FrameReframer?, to sampleBuffer: CMSampleBuffer,
                      cell: ReframeCell) -> CMSampleBuffer? {
        guard let reframer else { return sampleBuffer }
        return reframer.reframe(sampleBuffer: sampleBuffer, window: cell.window)
    }

    func reframe(sampleBuffer: CMSampleBuffer,
                 window: ReframeCell.Window) -> CMSampleBuffer? {
        guard let source = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return sampleBuffer
        }
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        guard window.isActive || width != outputWidth || height != outputHeight else {
            return sampleBuffer
        }
        let format = CVPixelBufferGetPixelFormatType(source)

        guard let surface = CVPixelBufferGetIOSurface(source)?.takeUnretainedValue()
        else {
            logOnce("surface", "FrameReframer: capture buffer has no IOSurface — passing frames through")
            return sampleBuffer
        }
        var wrapped: Unmanaged<CVPixelBuffer>?
        guard CVPixelBufferCreateWithIOSurface(kCFAllocatorDefault, surface, nil,
                                               &wrapped) == kCVReturnSuccess,
              let view = wrapped?.takeRetainedValue() else {
            logOnce("wrap", "FrameReframer: IOSurface wrap failed — passing frames through")
            return sampleBuffer
        }
        let apertureW = Double(Int(Double(width) / window.zoom) & ~1)
        let apertureH = Double(Int(Double(height) / window.zoom) & ~1)
        let aperture: [String: Any] = [
            kCVImageBufferCleanApertureWidthKey as String: apertureW,
            kCVImageBufferCleanApertureHeightKey as String: apertureH,
            kCVImageBufferCleanApertureHorizontalOffsetKey as String:
                ((window.x - 0.5) * Double(width)).rounded(),
            kCVImageBufferCleanApertureVerticalOffsetKey as String:
                ((window.y - 0.5) * Double(height)).rounded(),
        ]
        CVBufferSetAttachment(view, kCVImageBufferCleanApertureKey,
                              aperture as CFDictionary, .shouldNotPropagate)

        let key = "\(outputWidth)x\(outputHeight)/\(format)"
        if pool == nil || key != poolKey { rebuildPool(width: outputWidth, height: outputHeight, format: format, key: key) }
        guard let pool else { return sampleBuffer }
        var allocated: CVPixelBuffer?
        let aux = [kCVPixelBufferPoolAllocationThresholdKey as String: 6]
        let poolStatus = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
            kCFAllocatorDefault, pool, aux as CFDictionary, &allocated)
        if poolStatus == kCVReturnWouldExceedAllocationThreshold { return nil }
        guard poolStatus == kCVReturnSuccess, let output = allocated else {
            logOnce("pool-alloc", "FrameReframer: pool allocation failed (\(poolStatus)) — passing frames through")
            return sampleBuffer
        }

        let status = VTPixelTransferSessionTransferImage(session, from: view, to: output)
        guard status == noErr else {
            logOnce("transfer", "FrameReframer: pixel transfer failed (\(status)) — passing frames through")
            return sampleBuffer
        }

        CVBufferPropagateAttachments(source, output)
        if let cached = cachedFormatDescription,
           !CMVideoFormatDescriptionMatchesImageBuffer(cached, imageBuffer: output) {
            cachedFormatDescription = nil
        }
        if cachedFormatDescription == nil {
            var created: CMVideoFormatDescription?
            CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault, imageBuffer: output,
                formatDescriptionOut: &created)
            cachedFormatDescription = created
        }
        guard let formatDescription = cachedFormatDescription else { return sampleBuffer }
        var timing = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(sampleBuffer),
            presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
            decodeTimeStamp: .invalid)
        var result: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(
                allocator: kCFAllocatorDefault, imageBuffer: output,
                formatDescription: formatDescription, sampleTiming: &timing,
                sampleBufferOut: &result) == noErr, let result else {
            return sampleBuffer
        }
        return result
    }

    private func rebuildPool(width: Int, height: Int, format: OSType, key: String) {
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: format,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]
        var created: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(kCFAllocatorDefault, nil,
                                             attributes as CFDictionary, &created)
        pool = status == kCVReturnSuccess ? created : nil
        poolKey = key
        cachedFormatDescription = nil
        if pool == nil {
            logOnce("pool-create", "FrameReframer: pool creation failed (\(status)) — passing frames through")
        }
    }

    private func logOnce(_ stage: String, _ message: String) {
        guard loggedStages.insert(stage).inserted else { return }
        print(message)
    }
}
