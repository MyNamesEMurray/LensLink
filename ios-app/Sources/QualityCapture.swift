import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

final class QualityTap {
    private let lock = NSLock()
    private var capture: QualityCapture?

    func set(_ capture: QualityCapture?) {
        lock.lock()
        self.capture = capture
        lock.unlock()
    }

    func offer(_ sampleBuffer: CMSampleBuffer) {
        lock.lock()
        let capture = self.capture
        lock.unlock()
        capture?.offer(sampleBuffer)
    }
}

final class QualityCapture {
    struct Config {
        let name: String
        let codec: VideoCodec
        let prores: ProResFlavor?
        let bitrate: Int
        let maximum: Bool
        let qualityPriority: Bool
    }

    private struct Slot {
        let config: Config
        let encoder: VideoEncoder?
        var buffers: [CMSampleBuffer] = []
        var error: String?
    }

    let id: String
    private let frameTarget: Int
    private let width: Int32
    private let height: Int32
    private let fps: Int32
    private let capture422: Bool
    private let directory: URL
    private let referenceURL: URL
    private let lock = NSLock()
    private let writerQueue = DispatchQueue(label: "lenslink.quality.writer")
    private let finishQueue = DispatchQueue(label: "lenslink.quality.finish")
    private var slots: [Slot] = []
    private var reference: FileHandle?
    private var pixelFormat: OSType = 0
    private var captured = 0
    private var skipped = 0
    private var pendingWrites = 0
    private var finishing = false
    private var statusText = "starting"

    var onReady: (([(name: String, url: URL)]) -> Void)?
    var onStatusChange: (() -> Void)?

    var status: String {
        lock.lock()
        defer { lock.unlock() }
        return statusText
    }

    init(id: String, frames: Int, width: Int32, height: Int32, fps: Int32,
         capture422: Bool, configs: [Config]) throws {
        self.id = id
        self.frameTarget = frames
        self.width = width
        self.height = height
        self.fps = fps
        self.capture422 = capture422
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quality-\(id)", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        referenceURL = directory.appendingPathComponent("reference.yuv")
        FileManager.default.createFile(atPath: referenceURL.path, contents: nil)
        reference = try FileHandle(forWritingTo: referenceURL)

        for (index, config) in configs.enumerated() {
            let encoder = VideoEncoder(codec: config.codec, width: width, height: height,
                                       fps: fps, bitrate: config.bitrate, color: .sdr,
                                       maximumQuality: config.maximum,
                                       qualityPriority: config.qualityPriority,
                                       prores: config.prores)
            encoder.realTime = false
            encoder.onCompressedSampleBuffer = { [weak self] buffer in
                self?.collect(buffer, slot: index)
            }
            do {
                try encoder.start()
                slots.append(Slot(config: config, encoder: encoder))
            } catch {
                slots.append(Slot(config: config, encoder: nil,
                                  error: error.localizedDescription))
            }
        }
        statusText = "capturing 0/\(frames)"
    }

    private func collect(_ buffer: CMSampleBuffer, slot: Int) {
        lock.lock()
        slots[slot].buffers.append(buffer)
        lock.unlock()
    }

    func offer(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lock.lock()
        if finishing {
            lock.unlock()
            return
        }
        if pendingWrites > 6 {
            skipped += 1
            lock.unlock()
            return
        }
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        if pixelFormat == 0 {
            pixelFormat = format
        }
        guard format == pixelFormat, Self.ffmpegPixelFormat(format) != nil,
              CVPixelBufferGetWidth(pixelBuffer) == Int(width),
              CVPixelBufferGetHeight(pixelBuffer) == Int(height) else {
            finishing = true
            statusText = "error: unsupported frames (\(format))"
            lock.unlock()
            onStatusChange?()
            return
        }
        captured += 1
        pendingWrites += 1
        let done = captured >= frameTarget
        if done {
            finishing = true
        }
        statusText = "capturing \(captured)/\(frameTarget)"
        let encoders = slots.compactMap { $0.encoder }
        lock.unlock()

        let data = Self.copyPlanes(pixelBuffer)
        writerQueue.async { [weak self] in
            guard let self else { return }
            self.reference?.write(data)
            self.lock.lock()
            self.pendingWrites -= 1
            self.lock.unlock()
        }
        for encoder in encoders {
            encoder.encode(sampleBuffer)
        }
        if done {
            finishQueue.async { [weak self] in self?.finish() }
        }
    }

    private static func ffmpegPixelFormat(_ format: OSType) -> String? {
        switch format {
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange: return "nv12"
        case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange: return "p010le"
        case kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange: return "p210le"
        default: return nil
        }
    }

    private static func copyPlanes(_ pixelBuffer: CVPixelBuffer) -> Data {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let sampleBytes = format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ? 1 : 2
        var data = Data()
        for plane in 0..<CVPixelBufferGetPlaneCount(pixelBuffer) {
            guard let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, plane) else {
                continue
            }
            let rows = CVPixelBufferGetHeightOfPlane(pixelBuffer, plane)
            let stride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, plane)
            let planeWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, plane)
            let rowBytes = planeWidth * (plane == 0 ? 1 : 2) * sampleBytes
            data.reserveCapacity(data.count + rowBytes * rows)
            for row in 0..<rows {
                data.append(base.advanced(by: row * stride)
                                .assumingMemoryBound(to: UInt8.self),
                            count: rowBytes)
            }
        }
        return data
    }

    private func setStatus(_ text: String) {
        lock.lock()
        statusText = text
        lock.unlock()
        onStatusChange?()
    }

    private func finish() {
        for slot in slots {
            slot.encoder?.stop()
        }
        writerQueue.sync {}
        try? reference?.close()
        reference = nil

        lock.lock()
        let failedEarly = statusText.hasPrefix("error")
        let snapshot = slots
        let frames = captured
        let skippedFrames = skipped
        let format = pixelFormat
        lock.unlock()
        if failedEarly {
            return
        }

        setStatus("writing")
        var files: [(name: String, url: URL)] = [("reference.yuv", referenceURL)]
        var configs: [[String: Any]] = []
        for slot in snapshot {
            let config = slot.config
            let file = "\(config.name).mov"
            var entry: [String: Any] = [
                "name": config.name,
                "file": file,
                "codec": config.prores == nil ? config.codec.rawValue : "prores",
                "prores": config.prores?.rawValue ?? "",
                "bitrateMbps": Double(config.bitrate) / 1_000_000,
                "maximum": config.maximum,
                "qualityPriority": config.qualityPriority,
                "frames": slot.buffers.count,
                "errors": slot.encoder?.encodeErrorSummary().count ?? 0,
            ]
            var error = slot.error
            if error == nil, !slot.buffers.isEmpty {
                let url = directory.appendingPathComponent(file)
                if let problem = Self.writeMovie(slot.buffers, to: url) {
                    error = problem
                } else {
                    files.append((file, url))
                    let bytes = slot.buffers.reduce(0) {
                        $0 + CMSampleBufferGetTotalSampleSize($1)
                    }
                    entry["bytes"] = bytes
                }
            } else if error == nil {
                error = "encoder produced no frames"
            }
            if let error {
                entry["error"] = error
            }
            configs.append(entry)
        }
        lock.lock()
        for index in slots.indices {
            slots[index].buffers.removeAll()
        }
        lock.unlock()

        let manifest: [String: Any] = [
            "id": id,
            "width": Int(width),
            "height": Int(height),
            "fps": Int(fps),
            "frames": frames,
            "skipped": skippedFrames,
            "pixfmt": Self.ffmpegPixelFormat(format) ?? "",
            "capture422": capture422,
            "reference": "reference.yuv",
            "configs": configs,
        ]
        let manifestURL = directory.appendingPathComponent("manifest.json")
        guard let json = try? JSONSerialization.data(withJSONObject: manifest,
                                                     options: [.prettyPrinted]),
              (try? json.write(to: manifestURL)) != nil else {
            setStatus("error: could not write the manifest")
            return
        }
        files.append(("manifest.json", manifestURL))
        setStatus("sending")
        onReady?(files)
    }

    func transferFinished(ok: Bool) {
        setStatus(ok ? "done" : "error: transfer interrupted")
        try? FileManager.default.removeItem(at: directory)
    }

    func cancel() {
        lock.lock()
        finishing = true
        lock.unlock()
        for slot in slots {
            slot.encoder?.stop()
        }
        writerQueue.async { [weak self] in
            try? self?.reference?.close()
            self?.reference = nil
            if let directory = self?.directory {
                try? FileManager.default.removeItem(at: directory)
            }
        }
    }

    private static func writeMovie(_ buffers: [CMSampleBuffer], to url: URL) -> String? {
        guard let first = buffers.first,
              let format = CMSampleBufferGetFormatDescription(first) else {
            return "no format description"
        }
        do {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: nil,
                                           sourceFormatHint: format)
            input.expectsMediaDataInRealTime = false
            guard writer.canAdd(input) else { return "writer refused the track" }
            writer.add(input)
            guard writer.startWriting() else {
                return writer.error?.localizedDescription ?? "writer did not start"
            }
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(first))
            for buffer in buffers {
                while !input.isReadyForMoreMediaData {
                    usleep(2000)
                }
                if !input.append(buffer) {
                    return writer.error?.localizedDescription ?? "append failed"
                }
            }
            input.markAsFinished()
            let done = DispatchSemaphore(value: 0)
            writer.finishWriting { done.signal() }
            done.wait()
            return writer.status == .completed
                ? nil : (writer.error?.localizedDescription ?? "writer failed")
        } catch {
            return error.localizedDescription
        }
    }
}
