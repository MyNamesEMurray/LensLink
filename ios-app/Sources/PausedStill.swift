import AVFoundation
import CoreVideo

/// The picture the phone sends to OBS while a stream is held.
///
/// A paused stream sends no frames, and OBS keeps whatever it last had —
/// so a pause is indistinguishable from a stall: the same frozen picture,
/// no explanation. The fix belongs on this side of the wire. The plugin
/// tried drawing it, and could only do so for the standard decode path:
/// the GPU pipeline keeps frames in textures, with nothing to draw from.
/// Encoded here it is simply video, so every pipeline shows it and the
/// plugin needs no special case at all.
///
/// The blur is free: a 64×36 luma thumbnail, sampled from the live stream
/// about once a second, blown back up to frame size. No filter kernel, no
/// per-frame cost, and the result reads as deliberately obscured rather
/// than broken. Grey, because a held picture should not look like live
/// colour — the chroma planes are filled with neutral — and a pause glyph
/// on top so it reads at a glance from across a room.
///
/// Sampling at 1 Hz (rather than per frame) is what keeps this honest
/// against docs/PERFORMANCE.md: a few thousand reads a second, whatever
/// the resolution, and the still is at most a second stale — invisible
/// once it has been blurred to 64×36 anyway. It also means a still can
/// still be drawn when the camera has already been taken away, which is
/// exactly the case that started this: iOS interrupting capture while a
/// stream is up.
final class PausedStill: @unchecked Sendable {
    static let thumbWidth = 64
    static let thumbHeight = 36

    /// How far the still is pulled down from the live picture. Dim enough
    /// to read as inactive, bright enough to still show what the camera
    /// is pointed at.
    private static let dimNumerator = 45
    private static let dimDenominator = 100

    /// Video-range luma bounds: capture is video-range, so the still has
    /// to live between them or OBS shows crushed blacks.
    private static let lumaFloor = 16
    private static let lumaCeiling = 235

    private let lock = NSLock()
    private var thumb = [UInt8](repeating: 0,
                                count: thumbWidth * thumbHeight)
    private var haveThumb = false
    private var sourceFormat: OSType = 0
    private var lastSampleHostTime: CFTimeInterval = 0

    /// Capture queue, once per frame. Costs a timestamp comparison except
    /// about once a second, when it reads a few thousand luma samples.
    func note(_ sampleBuffer: CMSampleBuffer) {
        guard let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        let now = CACurrentMediaTime()
        lock.lock()
        let due = now - lastSampleHostTime >= 1.0
        if due {
            lastSampleHostTime = now
        }
        lock.unlock()
        guard due else { return }
        sample(pixels)
    }

    private func sample(_ pixels: CVPixelBuffer) {
        let width = CVPixelBufferGetWidth(pixels)
        let height = CVPixelBufferGetHeight(pixels)
        let format = CVPixelBufferGetPixelFormatType(pixels)
        guard width > 0, height > 0 else { return }

        guard CVPixelBufferLockBaseAddress(pixels, .readOnly) == kCVReturnSuccess
        else { return }
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }

        let planar = CVPixelBufferGetPlaneCount(pixels) > 0
        guard let base = planar
                ? CVPixelBufferGetBaseAddressOfPlane(pixels, 0)
                : CVPixelBufferGetBaseAddress(pixels) else { return }
        let rowBytes = planar
            ? CVPixelBufferGetBytesPerRowOfPlane(pixels, 0)
            : CVPixelBufferGetBytesPerRow(pixels)
        let tenBit = PausedStill.isTenBit(format)

        var sampled = [UInt8](repeating: 0,
                              count: PausedStill.thumbWidth *
                                     PausedStill.thumbHeight)
        for y in 0..<PausedStill.thumbHeight {
            let sourceRow = (y * height) / PausedStill.thumbHeight
            let row = base.advanced(by: sourceRow * rowBytes)
            for x in 0..<PausedStill.thumbWidth {
                let sourceColumn = (x * width) / PausedStill.thumbWidth
                let value: UInt8
                if tenBit {
                    // 10 bits in the high end of a 16-bit word (the x420 /
                    // x422 layout); the low byte is the fractional part we
                    // don't need.
                    let word = row.advanced(by: sourceColumn * 2)
                        .assumingMemoryBound(to: UInt16.self).pointee
                    value = UInt8(truncatingIfNeeded: word >> 8)
                } else {
                    value = row.advanced(by: sourceColumn)
                        .assumingMemoryBound(to: UInt8.self).pointee
                }
                sampled[y * PausedStill.thumbWidth + x] = value
            }
        }

        lock.lock()
        thumb = sampled
        haveThumb = true
        sourceFormat = format
        lock.unlock()
    }

    /// Builds the still at the stream's own size and pixel format, so the
    /// encoder takes it exactly as it takes a camera frame. A stream that
    /// never delivered a frame has nothing to hold.
    func makeFrame(width: Int, height: Int) -> CVPixelBuffer? {
        lock.lock()
        let ready = haveThumb
        let snapshot = thumb
        let format = sourceFormat
        lock.unlock()
        guard ready, width > 0, height > 0 else { return nil }

        var buffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ]
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, format,
                                  attributes as CFDictionary,
                                  &buffer) == kCVReturnSuccess,
              let pixels = buffer,
              CVPixelBufferLockBaseAddress(pixels, []) == kCVReturnSuccess
        else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(pixels, []) }

        let tenBit = PausedStill.isTenBit(format)
        guard let luma = CVPixelBufferGetBaseAddressOfPlane(pixels, 0) else {
            return nil
        }
        let lumaRowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixels, 0)

        writeLuma(into: luma, rowBytes: lumaRowBytes, width: width,
                  height: height, tenBit: tenBit, thumb: snapshot)
        drawGlyph(into: luma, rowBytes: lumaRowBytes, width: width,
                  height: height, tenBit: tenBit)

        // Neutral chroma: grey, whatever the camera was looking at. The
        // plane's own dimensions come from CoreVideo, so 4:2:0 and 4:2:2
        // need no special case here.
        if CVPixelBufferGetPlaneCount(pixels) > 1,
           let chroma = CVPixelBufferGetBaseAddressOfPlane(pixels, 1) {
            let chromaRowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixels, 1)
            let chromaWidth = CVPixelBufferGetWidthOfPlane(pixels, 1)
            let chromaHeight = CVPixelBufferGetHeightOfPlane(pixels, 1)
            for y in 0..<chromaHeight {
                let row = chroma.advanced(by: y * chromaRowBytes)
                if tenBit {
                    let pairs = row.assumingMemoryBound(to: UInt16.self)
                    for x in 0..<(chromaWidth * 2) {
                        pairs[x] = 0x8000
                    }
                } else {
                    let pairs = row.assumingMemoryBound(to: UInt8.self)
                    for x in 0..<(chromaWidth * 2) {
                        pairs[x] = 128
                    }
                }
            }
        }

        return pixels
    }

    // MARK: - Drawing

    private func writeLuma(into base: UnsafeMutableRawPointer, rowBytes: Int,
                           width: Int, height: Int, tenBit: Bool,
                           thumb: [UInt8]) {
        let span = PausedStill.lumaCeiling - PausedStill.lumaFloor
        let tw = PausedStill.thumbWidth
        let th = PausedStill.thumbHeight
        // Dimmed, and mapped into video-range luma so OBS doesn't clip
        // the result to black.
        let mapped = thumb.map { value -> Int in
            PausedStill.lumaFloor + Int(value) * PausedStill.dimNumerator /
                PausedStill.dimDenominator * span / 255
        }
        var column0 = [Int](repeating: 0, count: width)
        var columnWeight = [Int](repeating: 0, count: width)
        for x in 0..<width {
            let fixed = x * (tw - 1) * 256 / max(1, width - 1)
            column0[x] = min(tw - 2, fixed >> 8)
            columnWeight[x] = fixed - column0[x] * 256
        }
        var blended = [Int](repeating: 0, count: tw)
        for y in 0..<height {
            let fixedY = y * (th - 1) * 256 / max(1, height - 1)
            let y0 = min(th - 2, fixedY >> 8)
            let wy = fixedY - y0 * 256
            for x in 0..<tw {
                blended[x] = (mapped[y0 * tw + x] * (256 - wy)
                              + mapped[(y0 + 1) * tw + x] * wy) >> 8
            }
            let row = base.advanced(by: y * rowBytes)
            for x in 0..<width {
                let c = column0[x]
                let wx = columnWeight[x]
                let value = (blended[c] * (256 - wx) + blended[c + 1] * wx) >> 8
                PausedStill.write(UInt8(clamping: value), to: row, at: x,
                                  tenBit: tenBit)
            }
        }
    }

    /// Two bars, centred, with a dark halo so they hold over a light or a
    /// dark picture without needing to know which it is.
    private func drawGlyph(into base: UnsafeMutableRawPointer, rowBytes: Int,
                           width: Int, height: Int, tenBit: Bool) {
        let shorter = min(width, height)
        let barHeight = shorter / 4
        let barWidth = shorter / 14
        let gap = shorter / 22
        guard barHeight > 0, barWidth > 0 else { return }

        let halo = max(1, barWidth / 6)
        let top = (height - barHeight) / 2
        let left = (width - (barWidth * 2 + gap)) / 2
        let bars = [left, left + barWidth + gap]

        for bar in bars {
            for y in (top - halo)..<(top + barHeight + halo) {
                guard y >= 0, y < height else { continue }
                let row = base.advanced(by: y * rowBytes)
                let insideY = y >= top && y < top + barHeight
                for x in (bar - halo)..<(bar + barWidth + halo) {
                    guard x >= 0, x < width else { continue }
                    let inside = insideY && x >= bar && x < bar + barWidth
                    PausedStill.write(inside ? 220 : 16, to: row, at: x,
                                      tenBit: tenBit)
                }
            }
        }
    }

    private static func write(_ value: UInt8,
                              to row: UnsafeMutableRawPointer, at x: Int,
                              tenBit: Bool) {
        if tenBit {
            // Back into the high end of the 16-bit word the 10-bit
            // formats store luma in.
            row.advanced(by: x * 2)
                .assumingMemoryBound(to: UInt16.self)
                .pointee = UInt16(value) << 8
        } else {
            row.advanced(by: x).assumingMemoryBound(to: UInt8.self)
                .pointee = value
        }
    }

    private static func isTenBit(_ format: OSType) -> Bool {
        switch format {
        case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
             kCVPixelFormatType_420YpCbCr10BiPlanarFullRange,
             kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange,
             kCVPixelFormatType_422YpCbCr10BiPlanarFullRange:
            return true
        default:
            return false
        }
    }
}
