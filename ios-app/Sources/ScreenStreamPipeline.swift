import AVFoundation
import CoreMedia
import Foundation
import os

/// Screen capture → encoder → plugin, shared by both front ends.
///
/// There are two ways to capture the screen on iOS and they differ only
/// above this line: the ReplayKit broadcast-upload extension (iOS 15+,
/// a separate process) and the in-process ScreenCaptureKit session
/// (iOS 27+, `ScreenCaptureSession`). Both hand over `CMSampleBuffer`s and
/// both want exactly this: encode video, convert system audio, ship both
/// to the plugin over the wire protocol with `kind: "screen"`, and report
/// a pipeline heartbeat. So it lives here once rather than twice.
///
/// System audio only, never the microphone, on both paths: a streamer
/// already has their real mic in OBS and sending the phone's would double
/// it. See docs/PROTOCOL.md.
final class ScreenStreamPipeline {
    /// A failure the user has to be told about, phrased for them. The
    /// ReplayKit front end turns this into `finishBroadcastWithError`
    /// (an extension has no UI of its own); the in-app front end shows it
    /// in the app.
    var onFatalError: ((String) -> Void)?

    let client = StreamClient()
    private var encoder: VideoEncoder?
    private var configuredWidth: Int32 = 0
    private var configuredHeight: Int32 = 0
    private let fps: Int32 = 60

    /// HEVC by default: it compresses screen/UI content ~40% smaller than
    /// H.264 at the same quality, cutting the wire bitrate. Devices without
    /// HEVC hardware encoding (pre-A10, i.e. older than iPhone 7) fall back
    /// to H.264 automatically, the plugin decodes whichever codec the video
    /// config announces, and its no-output watchdog handles GPU decoders
    /// that dislike the stream. Flip to `false` to A/B against H.264.
    private static let preferHEVC = true
    // static let → initialized exactly once, thread-safely (read from the
    // capture thread and the network queue).
    static let codec: VideoCodec =
        (preferHEVC && VideoEncoder.isSupported(.hevc)) ? .hevc : .h264

    private let log: Logger
    /// Names the front end in log lines and in the "OBS never dialled in"
    /// message, so a support log says which capture path produced it.
    private let frontEnd: String

    init(frontEnd: String, logSubsystem: String) {
        self.frontEnd = frontEnd
        self.log = Logger(subsystem: logSubsystem, category: "diag")
    }

    /// Pipeline counters, surfaced every few seconds to the OBS log (via the
    /// plugin) and os_log. Guarded by `countersLock`: the capture callbacks
    /// and the encoder callback touch them from different threads while the
    /// heartbeat task reads them.
    private struct Counters {
        var videoSamples = 0
        var encoderBuilds = 0
        var encodedFrames = 0
        var encodedKeyframes = 0
        var encoderErrors = 0
        var audioSamples = 0
        var dims = ""
        var codecName = ""
        /// Set when the plugin asks for a keyframe (e.g. after it swaps to
        /// software decoding); consumed on the capture thread, which owns
        /// the encoder. Guarded by the same lock so we never touch the
        /// encoder from the network queue.
        var pendingKeyframe = false
    }
    private let countersLock = NSLock()
    private var counters = Counters()
    private func withCounters<T>(_ body: (inout Counters) -> T) -> T {
        countersLock.lock()
        defer { countersLock.unlock() }
        return body(&counters)
    }
    private var diagTask: Task<Void, Never>?

    /// Canonical output: 48 kHz stereo signed-16-bit interleaved PCM.
    private let targetAudioFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: Double(OBSCProtocol.screenAudioSampleRate),
        channels: AVAudioChannelCount(OBSCProtocol.screenAudioChannels),
        interleaved: true)!
    private var audioConverter: AVAudioConverter?
    private var audioSourceFormat: AVAudioFormat?

    // MARK: - Lifecycle

    private var everConnected = false
    private var watchdog: Task<Void, Never>?
    /// Port-bind retries: the app frees port 9979 when screen capture
    /// begins (its remote-start standby listener shares it), but that
    /// release can race this bind. Touched only on the main queue.
    private var listenRetries = 0
    private var finished = false

    private func fail(_ message: String) {
        onFatalError?(message)
    }

    func start() {
        client.sourceKind = .screen
        client.onControl = { [weak self] data in
            self?.handleControl(data)
        }
        client.onStateChange = { [weak self] state in
            guard let self else { return }
            switch state {
            case .connected:
                self.everConnected = true
                self.watchdog?.cancel()
                // Fresh connection: re-send config (dimensions are known
                // once the first frame arrives) and force a keyframe so
                // OBS joins immediately.
                if self.configuredWidth > 0 {
                    self.client.sendVideoConfig(codec: Self.codec,
                                                width: self.configuredWidth,
                                                height: self.configuredHeight,
                                                fps: self.fps)
                }
                self.encoder?.requestKeyframe()
            case .failed(let message):
                // Most likely: port 9979 already taken because the LensLink
                // app's camera stream is running. One stream per device.
                // The app's idle standby listener also holds the port but
                // frees it as capture starts — retry briefly so that
                // hand-off can complete before declaring failure.
                DispatchQueue.main.async {
                    guard !self.finished else { return }
                    if !self.everConnected && self.listenRetries < 4 {
                        self.listenRetries += 1
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                            guard let self, !self.finished else { return }
                            self.client.start(port: OBSCProtocol.usbPort)
                        }
                        return
                    }
                    self.fail("Could not open the streaming port (\(message)). "
                        + "If the LensLink camera is streaming, stop it first — "
                        + "a device can send the camera or the screen, not both.")
                }
            default:
                break
            }
        }
        client.start(port: OBSCProtocol.usbPort)
        log.info("screen capture started (\(self.frontEnd, privacy: .public)), codec=\(Self.codec.rawValue, privacy: .public)")
        startDiagnostics()

        // OBS never dialling in used to fail silently; surface it instead,
        // with the listener's actual state so the message pinpoints which
        // layer broke (listener never ready / no connections arrived /
        // handshake failed).
        watchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard let self, !Task.isCancelled, !self.everConnected else { return }
            self.fail("OBS did not connect within 30 seconds "
                + "[\(self.client.debugStatus())]. Check OBS has a LensLink "
                + "Screen source pointing at this phone (USB, or this "
                + "phone's Wi-Fi IP) — a LensLink Camera source won't accept "
                + "a screen stream — and the camera stream isn't running.")
        }
    }

    func stop() {
        DispatchQueue.main.async { self.finished = true }
        watchdog?.cancel()
        diagTask?.cancel()
        encoder?.stop()
        encoder = nil
        client.disconnect()
    }

    /// Emits a pipeline heartbeat every 3 s: how many screen samples came in,
    /// how many frames we encoded and sent, plus the network snapshot. Goes
    /// to the OBS log (through the plugin) and os_log, so a stuck stream
    /// shows exactly which stage stopped moving. The plugin logs its own
    /// matching line, so both ends line up in one place.
    private func startDiagnostics() {
        diagTask?.cancel()
        diagTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let self, !Task.isCancelled else { return }
                let c = self.withCounters { $0 }
                let line = "vid samp=\(c.videoSamples) enc=\(c.encodedFrames) "
                    + "kf=\(c.encodedKeyframes) builds=\(c.encoderBuilds) "
                    + "encErr=\(c.encoderErrors) "
                    + "\(c.codecName)\(c.dims.isEmpty ? "" : " " + c.dims) "
                    + "aud=\(c.audioSamples) via=\(self.frontEnd) | "
                    + self.client.diagnosticsSnapshot()
                self.client.sendDiag(line)
                self.log.info("\(line, privacy: .public)")
            }
        }
    }

    /// Control messages from the plugin. The only one a screen stream acts
    /// on is a keyframe request (the plugin sends it after switching to
    /// software decoding so the picture comes back right away).
    private func handleControl(_ data: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
              let cmd = obj["cmd"] as? String else { return }
        if cmd == "keyframe" {
            withCounters { $0.pendingKeyframe = true }
            log.info("keyframe requested by plugin")
        }
    }

    // MARK: - Video

    func handleVideo(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let width = Int32(CVPixelBufferGetWidth(pixelBuffer))
        let height = Int32(CVPixelBufferGetHeight(pixelBuffer))
        withCounters { $0.videoSamples += 1 }

        // (Re)build the encoder on first frame and whenever the screen
        // rotates (dimensions swap). The encoder has fixed dimensions.
        // On a folding device this also covers opening and closing it —
        // the capture switches displays and the dimensions change with it.
        if encoder == nil || width != configuredWidth || height != configuredHeight {
            encoder?.stop()
            let enc = VideoEncoder(codec: Self.codec, width: width, height: height,
                                   fps: fps, bitrate: bitrate(width, height))
            enc.onEncodedFrame = { [weak self] frame in
                guard let self else { return }
                self.withCounters {
                    $0.encodedFrames += 1
                    if frame.isKeyframe { $0.encodedKeyframes += 1 }
                }
                self.client.sendVideoFrame(frame)
            }
            do {
                try enc.start()
            } catch {
                withCounters { $0.encoderErrors += 1 }
                log.error("encoder start failed at \(width)x\(height): \(error.localizedDescription, privacy: .public)")
                return
            }
            encoder = enc
            configuredWidth = width
            configuredHeight = height
            let br = bitrate(width, height)
            withCounters {
                $0.encoderBuilds += 1
                $0.dims = "\(width)x\(height)"
                $0.codecName = Self.codec.rawValue
            }
            log.info("encoder built \(width)x\(height) \(Self.codec.rawValue, privacy: .public) @ \(br / 1_000_000) Mbps")
            client.sendVideoConfig(codec: Self.codec, width: width, height: height,
                                   fps: fps)
        }
        // Honour a pending keyframe request here, on the capture thread that
        // owns the encoder (never from the network queue).
        let forceKeyframe = withCounters { (c: inout Counters) -> Bool in
            defer { c.pendingKeyframe = false }
            return c.pendingKeyframe
        }
        if forceKeyframe {
            encoder?.requestKeyframe()
        }
        encoder?.encode(sampleBuffer)
    }

    /// Screen content compresses well (lots of static regions), but detail
    /// scales with resolution; ~5 bits per pixel-second, clamped.
    private func bitrate(_ width: Int32, _ height: Int32) -> Int {
        let pixels = Int(width) * Int(height)
        return min(16_000_000, max(6_000_000, pixels * 5))
    }

    // MARK: - System audio

    func handleAudio(_ sampleBuffer: CMSampleBuffer) {
        withCounters { $0.audioSamples += 1 }
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer)
        else { return }
        // Non-failable initializer — returns AVAudioFormat, not an optional.
        let sourceFormat = AVAudioFormat(cmAudioFormatDescription: formatDescription)

        if audioConverter == nil || audioSourceFormat != sourceFormat {
            audioConverter = AVAudioConverter(from: sourceFormat, to: targetAudioFormat)
            audioSourceFormat = sourceFormat
        }
        guard let converter = audioConverter else { return }

        let frames = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frames > 0,
              let input = AVAudioPCMBuffer(pcmFormat: sourceFormat,
                                           frameCapacity: AVAudioFrameCount(frames))
        else { return }
        input.frameLength = input.frameCapacity
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frames),
            into: input.mutableAudioBufferList) == noErr else { return }

        let ratio = targetAudioFormat.sampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(frames) * ratio) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: targetAudioFormat,
                                            frameCapacity: capacity) else { return }

        var error: NSError?
        var provided = false
        converter.convert(to: output, error: &error) { _, status in
            if provided {
                status.pointee = .noDataNow
                return nil
            }
            provided = true
            status.pointee = .haveData
            return input
        }
        guard error == nil, output.frameLength > 0 else { return }

        // Interleaved target → a single buffer holds the PCM bytes.
        let buffer = output.audioBufferList.pointee.mBuffers
        guard let data = buffer.mData else { return }
        let pcm = Data(bytes: data, count: Int(buffer.mDataByteSize))

        // Same clock as the video frames' pts, so OBS keeps A/V in sync.
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let ptsNs = UInt64(max(0, CMTimeGetSeconds(pts)) * 1_000_000_000)
        client.sendScreenAudio(pcm, ptsNanoseconds: ptsNs)
    }
}
