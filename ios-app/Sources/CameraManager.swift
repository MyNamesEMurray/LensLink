import Foundation
import AVFoundation
import UIKit
import os

/// Owns the AVCaptureSession and delivers raw camera frames.
final class CameraManager: NSObject {
    enum Resolution: String, CaseIterable, Identifiable {
        case hd720 = "720p"
        case hd1080 = "1080p"
        case uhd4k = "4K"

        var id: String { rawValue }

        var size: (width: Int32, height: Int32) {
            switch self {
            case .hd720: return (1280, 720)
            case .hd1080: return (1920, 1080)
            case .uhd4k: return (3840, 2160)
            }
        }

        func bitrate(for codec: VideoCodec,
                     color: StreamColor = .sdr) -> Int {
            let h264: Int
            switch self {
            case .hd720: h264 = 4_000_000
            case .hd1080: h264 = 8_000_000
            case .uhd4k: h264 = 30_000_000
            }
            // HEVC reaches comparable quality at roughly 60% of the bits.
            let base = codec == .hevc ? h264 * 6 / 10 : h264
            switch color {
            case .sdr:
                return base
            case .hlg, .log:
                // 10-bit carries more data per pixel; give it headroom.
                return base * 5 / 4
            }
        }
    }

    let session = AVCaptureSession()

    /// Set on the main thread, read per frame on the capture queue —
    /// hence the lock (a bare closure var is a data race at stop time).
    var onSampleBuffer: ((CMSampleBuffer) -> Void)? {
        get { callbackLock.lock(); defer { callbackLock.unlock() }
              return _onSampleBuffer }
        set { callbackLock.lock(); defer { callbackLock.unlock() }
              _onSampleBuffer = newValue }
    }
    private var _onSampleBuffer: ((CMSampleBuffer) -> Void)?
    private let callbackLock = NSLock()

    /// Latest synchronized depth frame while depth assist is active
    /// (green screen). Same locking pattern as `onSampleBuffer`: set on
    /// the main thread, read per frame on the capture queue. Depth runs
    /// slower than video, so this fires less often than `onSampleBuffer`
    /// (and never when depth assist is off).
    var onDepthData: ((AVDepthData) -> Void)? {
        get { callbackLock.lock(); defer { callbackLock.unlock() }
              return _onDepthData }
        set { callbackLock.lock(); defer { callbackLock.unlock() }
              _onDepthData = newValue }
    }
    private var _onDepthData: ((AVDepthData) -> Void)?

    /// Capture was interrupted (phone call, Camera app, Split View) or
    /// resumed. Delivered on the main queue.
    var onInterruption: ((Bool) -> Void)?

    /// The device currently feeding the session; camera controls act on it.
    private(set) var activeDevice: AVCaptureDevice?

    /* Internal (not private): the preview layer attaches/detaches its
     * session on this queue too — doing that on the main thread contends
     * with start/stopRunning and freezes the UI for seconds. */
    let sessionQueue = DispatchQueue(label: "obscam.session")
    private let videoQueue = DispatchQueue(label: "obscam.video")
    private var videoOutput: AVCaptureVideoDataOutput?

    /// Depth-assist plumbing (green screen). The synchronizer must stay
    /// retained in a property or synchronized delivery silently stops.
    private var depthOutput: AVCaptureDepthDataOutput?
    private var outputSynchronizer: AVCaptureDataOutputSynchronizer?

    /// True only when the depth path fully armed during the last
    /// configure: depth sibling device selected, a depth-capable format
    /// matched the EXACT requested resolution+fps, and the synchronizer
    /// replaced the plain video delegate. False = segmentation-only
    /// (graceful degrade). Valid once configure() has returned.
    private(set) var depthAssistActive = false

    override init() {
        super.init()
        // Without these observers a phone call or the Camera app grabbing
        // the hardware stops capture permanently while the UI says "Live".
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(sessionInterrupted),
                           name: .AVCaptureSessionWasInterrupted,
                           object: session)
        center.addObserver(self, selector: #selector(sessionResumed),
                           name: .AVCaptureSessionInterruptionEnded,
                           object: session)
        center.addObserver(self, selector: #selector(sessionRuntimeError),
                           name: .AVCaptureSessionRuntimeError,
                           object: session)
    }

    @objc private func sessionInterrupted(_ note: Notification) {
        DispatchQueue.main.async { self.onInterruption?(true) }
    }

    @objc private func sessionResumed(_ note: Notification) {
        start() // the session does not restart itself
        DispatchQueue.main.async { self.onInterruption?(false) }
    }

    @objc private func sessionRuntimeError(_ note: Notification) {
        // Media services reset and similar: restarting the session is the
        // documented recovery.
        start()
    }

    static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    /// A physical camera the user can pick (Main / Ultra Wide / Telephoto /
    /// Front — whatever this device actually has).
    struct Lens: Identifiable, Equatable, Hashable {
        let deviceType: AVCaptureDevice.DeviceType
        let position: AVCaptureDevice.Position
        let label: String

        var id: String {
            "\(position == .front ? "front" : "back"):\(deviceType.rawValue)"
        }
    }

    /// Enumerates the cameras present on this device, back lenses first
    /// (Main, Ultra Wide, Telephoto), then front.
    static func availableLenses() -> [Lens] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera,
                          .builtInTelephotoCamera],
            mediaType: .video,
            position: .unspecified)

        func rank(_ device: AVCaptureDevice) -> Int {
            let positionRank = device.position == .front ? 10 : 0
            switch device.deviceType {
            case .builtInWideAngleCamera: return positionRank + 0
            case .builtInUltraWideCamera: return positionRank + 1
            default: return positionRank + 2
            }
        }

        return discovery.devices
            .sorted { rank($0) < rank($1) }
            .map { device in
                Lens(deviceType: device.deviceType,
                     position: device.position,
                     label: label(for: device))
            }
    }

    private static func label(for device: AVCaptureDevice) -> String {
        if device.position == .front { return "Front" }
        switch device.deviceType {
        case .builtInUltraWideCamera: return "Ultra Wide (0.5×)"
        case .builtInTelephotoCamera: return "Telephoto"
        default: return "Main (Wide)"
        }
    }

    static let defaultLens = Lens(deviceType: .builtInWideAngleCamera,
                                  position: .back, label: "Main (Wide)")

    static func device(for lens: Lens) -> AVCaptureDevice? {
        AVCaptureDevice.default(lens.deviceType, for: .video,
                                position: lens.position)
    }

    /// The depth-registered sibling of a user-facing lens: TrueDepth for
    /// the front camera, LiDAR for the rear Main (Wide) lens — Apple
    /// registers their depth maps to exactly those YUV cameras. Ultra
    /// Wide and Telephoto have no depth sibling, and LiDAR needs
    /// iOS 15.4 (`.builtInLiDARDepthCamera` doesn't exist below that).
    /// nil = depth assist unavailable; capture stays on the normal
    /// device, segmentation-only.
    private static func depthSiblingDevice(for lens: Lens) -> AVCaptureDevice? {
        if lens.position == .front {
            return AVCaptureDevice.default(.builtInTrueDepthCamera,
                                           for: .video, position: .front)
        }
        if lens.position == .back,
           lens.deviceType == .builtInWideAngleCamera {
            if #available(iOS 15.4, *) {
                return AVCaptureDevice.default(.builtInLiDARDepthCamera,
                                               for: .video, position: .back)
            }
        }
        return nil
    }

    private static func format(for device: AVCaptureDevice,
                               resolution: Resolution,
                               fps: Int32,
                               color: StreamColor,
                               requireDepth: Bool = false) -> AVCaptureDevice.Format? {
        let target = resolution.size
        // Require exact dimensions and a frame-rate range covering the
        // requested rate; earlier formats (unbinned, video-range) win ties.
        // HLG additionally requires a 10-bit (x420) format that can
        // capture BT.2020 HLG; Apple Log a 10-bit 4:2:2 (x422) format
        // that can capture .appleLog — nil (unsupported) if none exists.
        // SDR considers every format, exactly as before colour existed.
        // `requireDepth` (depth assist) additionally requires a format
        // that can pair with a depth stream — the depth sibling devices
        // carry both depth-capable and depth-less formats.
        let candidates = device.formats.filter { format in
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard dims.width == target.width, dims.height == target.height else {
                return false
            }
            if requireDepth, format.supportedDepthDataFormats.isEmpty {
                return false
            }
            switch color {
            case .sdr:
                break
            case .hlg:
                guard CMFormatDescriptionGetMediaSubType(format.formatDescription)
                        == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
                      format.supportedColorSpaces.contains(.HLG_BT2020) else {
                    return false
                }
            case .log:
                // Log-capable device formats are x422, NOT the x420 HLG
                // uses. `.appleLog` is iOS 17+; below that there are no
                // candidates, so Log degrades/clamps exactly like an
                // HLG-less combo does.
                guard #available(iOS 17.0, *) else { return false }
                guard CMFormatDescriptionGetMediaSubType(format.formatDescription)
                        == kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange,
                      format.supportedColorSpaces.contains(.appleLog) else {
                    return false
                }
            }
            return format.videoSupportedFrameRateRanges
                .contains { $0.maxFrameRate >= Double(fps) }
        }
        guard let first = candidates.first else { return nil }

        // The device list carries near-duplicate formats whose practical
        // difference is whether the system video effects (Control Center:
        // Portrait, Studio Light, Reactions; Center Stage on iPad) can
        // run — usually only the sensor-binned sibling supports them, and
        // picking the other one leaves the user's Video Effects panel
        // empty, which reads as a bug. Prefer the effect-capable sibling,
        // but only with the same pixel format (colour range must never
        // shift with this choice). The effects cost nothing unless the
        // user actually switches one on.
        let subtype = CMFormatDescriptionGetMediaSubType(first.formatDescription)
        var best = first
        var bestScore = effectsScore(first)
        for candidate in candidates.dropFirst()
        where CMFormatDescriptionGetMediaSubType(candidate.formatDescription) == subtype {
            let score = effectsScore(candidate)
            if score > bestScore {
                best = candidate
                bestScore = score
            }
        }
        // Unified-log breadcrumb (Console.app when a Mac is handy; the
        // full copyable table lives in Options → Camera diagnostics):
        // the candidate list with effect flags, so "Video Effects panel
        // is empty on <device>" is diagnosable instead of guessed at.
        for candidate in candidates {
            let line = "Format \(target.width)x\(target.height)@\(fps) "
                + "binned=\(candidate.isVideoBinned) "
                + "effects=\(effectsScore(candidate))"
                + (candidate == best ? " <- chosen" : "")
            log.info("\(line, privacy: .public)")
        }
        return best
    }

    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "LensLink",
        category: "camera")

    /// Human-readable dump of every lens's capture formats with the
    /// system video-effect flags (CS = Center Stage, P = Portrait,
    /// SL = Studio Light, R = Reactions) — the field diagnostic behind
    /// Options → Camera diagnostics, copyable straight from the phone.
    static func formatReport() -> String {
        var out = ["\(UIDevice.current.model) — iOS "
                   + UIDevice.current.systemVersion,
                   "flags: binned / CS / P / SL / R / colour / depth", ""]
        for lens in availableLenses() {
            guard let device = device(for: lens) else { continue }
            out.append("== \(lens.label) ==")
            appendFormatRows(of: device, to: &out)
            out.append("")
        }
        // The depth-sibling devices (green screen's depth assist) carry
        // their own format tables, different from the plain lenses above.
        // Dump them under their own headers so device reports answer
        // which resolution+fps combos can actually carry depth.
        var depthSiblings: [(String, AVCaptureDevice)] = []
        if let trueDepth = AVCaptureDevice.default(.builtInTrueDepthCamera,
                                                   for: .video,
                                                   position: .front) {
            depthSiblings.append(("Front TrueDepth (depth sibling)",
                                  trueDepth))
        }
        if #available(iOS 15.4, *),
           let lidar = AVCaptureDevice.default(.builtInLiDARDepthCamera,
                                               for: .video,
                                               position: .back) {
            depthSiblings.append(("Rear LiDAR (depth sibling)", lidar))
        }
        for (title, device) in depthSiblings {
            out.append("== \(title) ==")
            appendFormatRows(of: device, to: &out)
            out.append("")
        }
        return out.joined(separator: "\n")
    }

    /// One diagnostics row per capture format of `device` — shared by
    /// the user-facing lens dumps and the depth-sibling dumps above.
    private static func appendFormatRows(of device: AVCaptureDevice,
                                         to out: inout [String]) {
        for format in device.formats {
            let dims = CMVideoFormatDescriptionGetDimensions(
                format.formatDescription)
            let maxFps = format.videoSupportedFrameRateRanges
                .map(\.maxFrameRate).max() ?? 0
            var flags = [format.isVideoBinned ? "b" : "-",
                         format.isCenterStageSupported ? "CS" : "--",
                         format.isPortraitEffectSupported ? "P" : "-"]
            if #available(iOS 16.0, *) {
                flags.append(format.isStudioLightSupported ? "SL" : "--")
            } else {
                flags.append("?")
            }
            if #available(iOS 17.0, *) {
                flags.append(format.reactionEffectsSupported ? "R" : "-")
            } else {
                flags.append("?")
            }
            flags.append(colourFlags(format))
            flags.append(depthFlags(format))
            out.append(String(format: "%5dx%-5d fps<=%-3.0f  %@",
                              dims.width, dims.height, maxFps,
                              flags.joined(separator: " ")))
        }
    }

    /// Depth column of the diagnostics table: the largest depth map this
    /// video format can pair with ("D320x240"), or "-" when it supports
    /// no depth at all. This is the per-device truth behind which
    /// combos can run depth assist, the same way the colour column is
    /// for HDR/Log.
    private static func depthFlags(_ format: AVCaptureDevice.Format) -> String {
        let dims = format.supportedDepthDataFormats.map {
            CMVideoFormatDescriptionGetDimensions($0.formatDescription)
        }
        guard let best = dims.max(by: {
            $0.width * $0.height < $1.width * $1.height
        }) else { return "-" }
        return "D\(best.width)x\(best.height)"
    }

    /// Colour column of the diagnostics table: the format's bit depth
    /// plus the HDR/Log colour spaces it can capture. This is the
    /// per-device truth behind the colour picker's HDR and Apple Log
    /// choices, the same way the effect flags are for Video Effects.
    private static func colourFlags(_ format: AVCaptureDevice.Format) -> String {
        let subtype = CMFormatDescriptionGetMediaSubType(
            format.formatDescription)
        // x422 is the Apple Log capture subtype — 10-bit like the x420s.
        let tenBit = subtype == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
            || subtype == kCVPixelFormatType_420YpCbCr10BiPlanarFullRange
            || subtype == kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange
        var flags = [tenBit ? "10bit" : "8bit "]
        if format.supportedColorSpaces.contains(.HLG_BT2020) {
            flags.append("HLG")
        }
        if #available(iOS 17.0, *),
           format.supportedColorSpaces.contains(.appleLog) {
            flags.append("Log")
        }
        return flags.joined(separator: " ")
    }

    /// How many of the system video effects this format can run. The
    /// effects themselves are user-toggled in Control Center — apps can't
    /// switch them on, only pick a format that permits them.
    private static func effectsScore(_ format: AVCaptureDevice.Format) -> Int {
        var score = 0
        if format.isCenterStageSupported { score += 1 }
        if format.isPortraitEffectSupported { score += 1 }
        if #available(iOS 16.0, *), format.isStudioLightSupported {
            score += 1
        }
        if #available(iOS 17.0, *), format.reactionEffectsSupported {
            score += 1
        }
        return score
    }

    /// Whether this lens can capture the resolution at the frame rate
    /// (in the given colour pipeline). Drives the app's pickers so
    /// unsupported combos are never offered.
    static func supports(resolution: Resolution, fps: Int32,
                         lens: Lens, color: StreamColor = .sdr) -> Bool {
        guard let device = device(for: lens) else { return false }
        return format(for: device, resolution: resolution, fps: fps,
                      color: color) != nil
    }

    /// Whether this combo has a 10-bit HLG capture format — the UI's
    /// gate for what the HDR choice can actually deliver.
    static func hdrAvailable(lens: Lens, resolution: Resolution,
                             fps: Int32) -> Bool {
        supports(resolution: resolution, fps: fps, lens: lens, color: .hlg)
    }

    /// Whether any lens on this device has an Apple Log capture format —
    /// the UI's gate for offering the Apple Log choice at all. Always
    /// false below iOS 17 (`.appleLog` doesn't exist there). Cached like
    /// `VideoEncoder.hdrSupported`: it walks every lens's format table,
    /// far too expensive to run per SwiftUI render of the picker.
    static let appleLogCaptureAvailable: Bool = {
        guard #available(iOS 17.0, *) else { return false }
        return availableLenses().contains { lens in
            guard let device = device(for: lens) else { return false }
            return device.formats.contains {
                $0.supportedColorSpaces.contains(.appleLog)
            }
        }
    }()

    /// Fires on system-pressure (thermal/power) level changes, on the
    /// main queue — Streamer scales the bitrate down in response.
    var onSystemPressure: ((AVCaptureDevice.SystemPressureState.Level) -> Void)?
    private var pressureObservation: NSKeyValueObservation?
    private var configuredFps: Int32 = 30
    private var configuredFrameRateLock = true
    private var fpsThrottled = false

    private func systemPressureChanged(on device: AVCaptureDevice) {
        let level = device.systemPressureState.level
        let line = "System pressure: \(level.rawValue)"
        Self.log.warning("\(line, privacy: .public)")
        sessionQueue.async { [weak self] in
            guard let self else { return }
            // Halve the frame rate at .critical (60→30, 30→15) — losing
            // cadence beats losing the capture to a thermal shutdown —
            // and restore the configured rate once pressure abates.
            let throttle = level == .critical
            if throttle != self.fpsThrottled {
                self.fpsThrottled = throttle
                self.applyFrameRate(divisor: throttle ? 2 : 1)
            }
        }
        DispatchQueue.main.async { self.onSystemPressure?(level) }
    }

    /// sessionQueue only.
    private func applyFrameRate(divisor: CMTimeValue) {
        guard let device = activeDevice else { return }
        let duration = CMTime(value: divisor,
                              timescale: configuredFps)
        do {
            try device.lockForConfiguration()
            device.activeVideoMinFrameDuration = duration
            // Min alone caps the rate; pinning max too is the cadence
            // lock. When the video-effects experiment has unlocked max,
            // keep it unlocked through thermal throttling as well — the
            // throttle's goal (a lower ceiling) is met by min, and
            // re-pinning max here would silently end the experiment
            // after one pressure episode.
            if configuredFrameRateLock {
                device.activeVideoMaxFrameDuration = duration
            }
            device.unlockForConfiguration()
        } catch {
            print("Frame-rate throttle failed: \(error.localizedDescription)")
        }
    }

    /// AVCaptureSession requires serialized access; start/stop run on
    /// `sessionQueue`, so configuration hops there too (synchronously, to
    /// keep the throwing API).
    /// Returns the colour pipeline actually configured: the capture
    /// output can refuse 10-bit delivery even when the device format
    /// supports HLG (see the degrade comment below), so callers must
    /// build the encoder and announce the stream from this value, never
    /// from the colour they asked for.
    @discardableResult
    func configure(lens: Lens,
                   resolution: Resolution,
                   fps: Int32,
                   lockFrameRate: Bool = true,
                   color: StreamColor = .sdr,
                   wantsDepth: Bool = false) throws -> StreamColor {
        try sessionQueue.sync {
            try configureOnQueue(lens: lens, resolution: resolution,
                                 fps: fps, lockFrameRate: lockFrameRate,
                                 color: color, wantsDepth: wantsDepth)
        }
    }

    private func configureOnQueue(lens: Lens,
                                  resolution: Resolution,
                                  fps: Int32,
                                  lockFrameRate: Bool,
                                  color: StreamColor,
                                  wantsDepth: Bool) throws -> StreamColor {
        let position = lens.position
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.inputs.forEach(session.removeInput)
        session.outputs.forEach(session.removeOutput)

        // Reset depth plumbing from any previous configuration; the
        // depth block below re-arms it only when everything lines up.
        depthOutput = nil
        outputSynchronizer = nil
        depthAssistActive = false

        // Format is chosen manually below; presets can't express 4K60.
        session.sessionPreset = .inputPriority

        // For HLG and Apple Log we set the device's colour space
        // ourselves below, so the session must not manage it (it would
        // override our choice on input changes). For SDR, automatic is
        // the iOS default — keeping it preserves the pre-HDR behaviour
        // exactly.
        switch color {
        case .sdr:
            session.automaticallyConfiguresCaptureDeviceForWideColor = true
        case .hlg, .log:
            session.automaticallyConfiguresCaptureDeviceForWideColor = false
        }

        guard var device = Self.device(for: lens) else {
            throw NSError(domain: "CameraManager", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Camera not available"])
        }
        // Depth assist (green screen): swap to the depth-registered
        // sibling device (TrueDepth / LiDAR) — the plain lenses have no
        // depth formats at all — but ONLY when the sibling has a
        // depth-capable format at the EXACT requested resolution+fps.
        // Otherwise stay on the normal device with depth off:
        // resolution/fps are NEVER changed to chase depth.
        var depthPinnedFormat: AVCaptureDevice.Format?
        if wantsDepth, let sibling = Self.depthSiblingDevice(for: lens),
           let siblingFormat = Self.format(for: sibling,
                                           resolution: resolution,
                                           fps: fps, color: color,
                                           requireDepth: true) {
            device = sibling
            depthPinnedFormat = siblingFormat
        }
        guard let format = depthPinnedFormat
                ?? Self.format(for: device, resolution: resolution,
                               fps: fps, color: color) else {
            throw NSError(domain: "CameraManager", code: 4,
                          userInfo: [NSLocalizedDescriptionKey:
                            "\(resolution.rawValue) at \(fps) fps is not supported by the \(lens.label) camera"])
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw NSError(domain: "CameraManager", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot add camera input"])
        }
        session.addInput(input)

        try device.lockForConfiguration()
        device.activeFormat = format
        switch color {
        case .sdr:
            // The session manages colour (automatic wide colour, above).
            break
        case .hlg:
            device.activeColorSpace = .HLG_BT2020
        case .log:
            if #available(iOS 17.0, *) {
                device.activeColorSpace = .appleLog
            }
            // No else: format(for:) has no Log candidates below iOS 17,
            // so configure has already thrown before reaching here.
        }
        // Min duration always caps the rate at the user's choice. The max
        // (the cadence lock, see PERFORMANCE.md) is normally pinned too —
        // but the "Allow system video effects" experiment leaves it at the
        // format default, giving iOS the downward flexibility the Control
        // Center effects appear to demand: the reproducing iPhone 15 Pro
        // shows effect-capable formats chosen and active, yet a blank
        // Video Effects panel — the lock is the last variable standing.
        let frameDuration = CMTime(value: 1, timescale: fps)
        device.activeVideoMinFrameDuration = frameDuration
        if lockFrameRate {
            device.activeVideoMaxFrameDuration = frameDuration
        }
        if depthPinnedFormat != nil {
            // Largest DepthFloat16 entry: meters directly, mapping to an
            // r16Float texture. Must come from the ACTIVE format's own
            // supportedDepthDataFormats — anything else throws an
            // (uncatchable) NSException. If no Float16 entry exists the
            // system default depth format applies; the compositor
            // converts defensively either way.
            let depthFormats = format.supportedDepthDataFormats.filter {
                CMFormatDescriptionGetMediaSubType($0.formatDescription)
                    == kCVPixelFormatType_DepthFloat16
            }
            if let best = depthFormats.max(by: {
                let a = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
                let b = CMVideoFormatDescriptionGetDimensions($1.formatDescription)
                return a.width * a.height < b.width * b.height
            }) {
                device.activeDepthDataFormat = best
            }
            // ~15 Hz depth is plenty for a distance cutoff and keeps the
            // added thermal/power load small. Set AFTER the formats —
            // changing either resets this duration.
            device.activeDepthDataMinFrameDuration = CMTime(value: 1,
                                                            timescale: 15)
        }
        device.unlockForConfiguration()
        activeDevice = device

        // Thermal/power mitigation, per the systemPressureState docs:
        // frame-rate throttling is Apple's recommended response, and at
        // .shutdown iOS stops capture on its own (surfaced through the
        // interruption observers above).
        configuredFps = fps
        configuredFrameRateLock = lockFrameRate
        fpsThrottled = false
        pressureObservation?.invalidate()
        pressureObservation = device.observe(\.systemPressureState,
                                             options: [.new]) {
            [weak self] observedDevice, _ in
            self?.systemPressureChanged(on: observedDevice)
        }

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        if depthPinnedFormat == nil {
            // The pre-existing (and only) delivery path whenever depth is
            // off; the synchronizer below REPLACES it in depth mode (the
            // two must never both be active).
            output.setSampleBufferDelegate(self, queue: videoQueue)
        }

        guard session.canAddOutput(output) else {
            throw NSError(domain: "CameraManager", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot add video output"])
        }
        session.addOutput(output)
        videoOutput = output

        if depthPinnedFormat != nil {
            let depth = AVCaptureDepthDataOutput()
            // Filtered depth avoids NaN holes punched through the
            // subject (the compositor's gate is NaN-safe regardless, but
            // filtering gives the smoother matte); late maps are
            // dropped, never queued.
            depth.isFilteringEnabled = true
            depth.alwaysDiscardsLateDepthData = true
            if session.canAddOutput(depth) {
                session.addOutput(depth)
                // One time-matched callback delivers video + depth on
                // the same capture queue.
                let synchronizer = AVCaptureDataOutputSynchronizer(
                    dataOutputs: [output, depth])
                synchronizer.setDelegate(self, queue: videoQueue)
                depthOutput = depth
                outputSynchronizer = synchronizer
                depthAssistActive = true
            } else {
                // Depth output refused: degrade to segmentation-only via
                // the ordinary delegate path.
                output.setSampleBufferDelegate(self, queue: videoQueue)
            }
        }

        // Video-range in every pipeline; only the depth/chroma differ.
        // Apple Log delivers x422 (the Log formats' native subtype);
        // VideoToolbox accepts x422 into a Main10 HEVC session and
        // converts internally, so the encoder needs no pixel-format
        // knowledge.
        let outputPixelFormat: OSType
        switch color {
        case .sdr:
            outputPixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        case .hlg:
            outputPixelFormat = kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
        case .log:
            outputPixelFormat = kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange
        }
        // The pixel format is chosen AFTER the output joins the session:
        // a detached output only advertises the generic 8-bit formats —
        // x420/x422 enter availableVideoPixelFormatTypes once the output
        // is connected to a device whose active format is 10-bit — and
        // assigning a format missing from that list raises an NSException
        // Swift cannot catch (the issue #81 TestFlight crash).
        if color != .sdr,
           !output.availableVideoPixelFormatTypes.contains(outputPixelFormat) {
            // Degrade to SDR rather than crash — and rebuild the whole
            // graph (begin/commit pairs nest) so the format choice,
            // colour space, and wide-colour management all match: 8-bit
            // capture behind a Main10 encode tagged for HLG or Log would
            // reach OBS with the wrong colours.
            return try configureOnQueue(lens: lens, resolution: resolution,
                                        fps: fps,
                                        lockFrameRate: lockFrameRate,
                                        color: .sdr,
                                        wantsDepth: wantsDepth)
        }
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: outputPixelFormat
        ]

        if let connection = output.connection(with: .video) {
            if connection.isVideoOrientationSupported {
                // Sensor-native landscape — the wire format LensLink has
                // always streamed. The phone's rotation affects only the
                // on-screen preview (CameraPreviewView), never the stream.
                connection.videoOrientation = .landscapeRight
            }
            // Stabilization buffers multiple frames inside the capture
            // pipeline — a large hidden latency cost for a live feed.
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .off
            }
            if position == .front, connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true
            }
        }
        // Mirror the video connection's geometry onto the depth stream
        // (when supported) so the depth map stays registered to the
        // video buffer instead of arriving rotated/flipped.
        if let depthConnection = depthOutput?.connection(with: .depthData) {
            if depthConnection.isVideoOrientationSupported {
                depthConnection.videoOrientation = .landscapeRight
            }
            if position == .front,
               depthConnection.isVideoMirroringSupported {
                depthConnection.isVideoMirrored = true
            }
        }
        return color
    }

    // MARK: - Live camera controls

    /// Runs `block` with the active device locked for configuration.
    private func withLockedDevice(_ block: (AVCaptureDevice) -> Void) {
        guard let device = activeDevice,
              (try? device.lockForConfiguration()) != nil else { return }
        block(device)
        device.unlockForConfiguration()
    }

    var maxZoomFactor: CGFloat {
        guard let device = activeDevice else { return 1 }
        // Beyond ~10x the digital zoom is mush; keep the slider useful.
        return min(device.activeFormat.videoMaxZoomFactor, 10)
    }

    func setZoom(_ factor: CGFloat) {
        // TODO(green screen depth assist): whether the streamed depth map
        // tracks videoZoomFactor crops is unconfirmed — under zoom the
        // compositor's depth gate may misalign with the video. Zoom is
        // deliberately left alone here (no clamping, no depth teardown);
        // `depthAssistActive` reports the state and the gate simply may
        // be off until this is verified on a real device.
        withLockedDevice { device in
            let clamped = max(device.minAvailableVideoZoomFactor,
                              min(factor, maxZoomFactor))
            device.videoZoomFactor = clamped
        }
    }

    var exposureBiasRange: ClosedRange<Float> {
        guard let device = activeDevice else { return -2...2 }
        let lower = max(device.minExposureTargetBias, -3)
        let upper = min(device.maxExposureTargetBias, 3)
        return lower...max(upper, lower + 0.1)
    }

    func setExposureBias(_ bias: Float) {
        withLockedDevice { device in
            let clamped = max(device.minExposureTargetBias,
                              min(bias, device.maxExposureTargetBias))
            device.setExposureTargetBias(clamped)
        }
    }

    /// `resetExposure` is false while manual exposure is active, so
    /// switching focus modes doesn't silently discard the ISO/shutter lock.
    func setContinuousAutoFocus(resetExposure: Bool = true) {
        withLockedDevice { device in
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if resetExposure,
               device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
        }
    }

    /// Locks focus, optionally at a specific lens position (0 = closest,
    /// 1 = infinity). Without a position, freezes focus where it is.
    func lockFocus(lensPosition: Float?) {
        withLockedDevice { device in
            if let lensPosition,
               device.isLockingFocusWithCustomLensPositionSupported {
                device.setFocusModeLocked(
                    lensPosition: max(0, min(lensPosition, 1)))
            } else if device.isFocusModeSupported(.locked) {
                device.focusMode = .locked
            }
        }
    }

    /// One-shot focus + exposure at a point of interest (0…1 device coords).
    /// `includeExposure` is false while manual exposure is active, so a
    /// focus tap doesn't discard the ISO/shutter lock.
    func focusAndExpose(at devicePoint: CGPoint, includeExposure: Bool = true) {
        withLockedDevice { device in
            if device.isFocusPointOfInterestSupported,
               device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusPointOfInterest = devicePoint
                device.focusMode = .continuousAutoFocus
            }
            if includeExposure,
               device.isExposurePointOfInterestSupported,
               device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposurePointOfInterest = devicePoint
                device.exposureMode = .continuousAutoExposure
            }
        }
    }

    // MARK: - White balance / manual exposure

    /// Whether the active camera supports locking white balance to custom
    /// gains (the temperature slider). Front cameras on some devices don't.
    var supportsWhiteBalanceLock: Bool {
        activeDevice?.isLockingWhiteBalanceWithCustomDeviceGainsSupported ?? false
    }

    func setAutoWhiteBalance() {
        withLockedDevice { device in
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
        }
    }

    /// Locks white balance at a colour temperature (Kelvin, neutral tint).
    func lockWhiteBalance(temperature: Float) {
        withLockedDevice { device in
            guard device.isLockingWhiteBalanceWithCustomDeviceGainsSupported
            else { return }
            let values = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
                temperature: temperature, tint: 0)
            var gains = device.deviceWhiteBalanceGains(for: values)
            // The conversion can produce gains outside the legal range at
            // extreme temperatures; setting those throws an exception.
            let maxGain = device.maxWhiteBalanceGain
            gains.redGain = max(1, min(gains.redGain, maxGain))
            gains.greenGain = max(1, min(gains.greenGain, maxGain))
            gains.blueGain = max(1, min(gains.blueGain, maxGain))
            device.setWhiteBalanceModeLocked(with: gains)
        }
    }

    var supportsManualExposure: Bool {
        activeDevice?.isExposureModeSupported(.custom) ?? false
    }

    /// ISO limits of the active format (manual exposure).
    var isoRange: ClosedRange<Float> {
        guard let device = activeDevice else { return 100...800 }
        let format = device.activeFormat
        return format.minISO...max(format.maxISO, format.minISO + 1)
    }

    var minShutterSeconds: Double {
        guard let device = activeDevice else { return 1.0 / 8000 }
        return device.activeFormat.minExposureDuration.seconds
    }

    /// Longest usable shutter: bounded by the format and by the frame
    /// interval (a shutter longer than a frame would drop the frame rate).
    func maxShutterSeconds(fps: Int32) -> Double {
        guard let device = activeDevice else { return 1.0 / 30 }
        return min(device.activeFormat.maxExposureDuration.seconds,
                   1.0 / Double(fps))
    }

    /// Manual exposure: fixed ISO and shutter. Values are clamped to the
    /// active format's limits.
    func setManualExposure(iso: Float, shutterSeconds: Double) {
        withLockedDevice { device in
            guard device.isExposureModeSupported(.custom) else { return }
            let format = device.activeFormat
            let clampedISO = max(format.minISO, min(iso, format.maxISO))
            let seconds = max(format.minExposureDuration.seconds,
                              min(shutterSeconds,
                                  format.maxExposureDuration.seconds))
            device.setExposureModeCustom(
                duration: CMTime(seconds: seconds,
                                 preferredTimescale: 1_000_000),
                iso: clampedISO)
        }
    }

    func setAutoExposure() {
        withLockedDevice { device in
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
        }
    }

    var hasFlashlight: Bool { activeDevice?.hasTorch ?? false }

    func setFlashlight(_ on: Bool) {
        withLockedDevice { device in
            guard device.hasTorch else { return }
            device.torchMode = on ? .on : .off
        }
    }

    func start() {
        sessionQueue.async { [session] in
            if !session.isRunning {
                session.startRunning()
            }
        }
    }

    func stop() {
        sessionQueue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        onSampleBuffer?(sampleBuffer)
    }
}

/// Depth mode only: the synchronizer replaces the plain sample-buffer
/// delegate above and delivers time-matched video + depth in one
/// callback on the same capture queue.
extension CameraManager: AVCaptureDataOutputSynchronizerDelegate {
    func dataOutputSynchronizer(
        _ synchronizer: AVCaptureDataOutputSynchronizer,
        didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection
    ) {
        // Resolve the outputs from the CALLBACK's own synchronizer, never
        // from self.videoOutput/self.depthOutput: those properties are
        // rewritten on sessionQueue during a reconfigure while this
        // callback runs on the capture queue — an unsynchronized
        // cross-queue read (and a callback holding the OLD synchronizer
        // could misresolve against the NEW outputs). Everything below is
        // callback-local state, so a mid-reconfigure delivery is safe.
        var syncedDepth: AVCaptureSynchronizedDepthData?
        var syncedVideo: AVCaptureSynchronizedSampleBufferData?
        for output in synchronizer.dataOutputs {
            switch synchronizedDataCollection.synchronizedData(for: output) {
            case let depth as AVCaptureSynchronizedDepthData:
                syncedDepth = depth
            case let video as AVCaptureSynchronizedSampleBufferData:
                syncedVideo = video
            default:
                break
            }
        }
        // Depth first, so the compositor holds the freshest map when the
        // matching video frame lands below. Depth legitimately runs
        // slower than video — many callbacks carry no depth at all, and
        // the consumer keeps reusing the last map.
        if let syncedDepth, !syncedDepth.depthDataWasDropped {
            onDepthData?(syncedDepth.depthData)
        }
        guard let syncedVideo, !syncedVideo.sampleBufferWasDropped else {
            return
        }
        onSampleBuffer?(syncedVideo.sampleBuffer)
    }
}
