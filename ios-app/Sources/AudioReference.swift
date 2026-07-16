import Foundation
import AVFoundation

/// Captures phone-mic audio, in one of two roles:
///
/// - `.lipSyncReference` (16 kHz mono): never played out — the plugin
///   cross-correlates it against the real microphone in OBS to measure
///   that mic's true latency and auto-calibrate lip sync.
/// - `.playback` (48 kHz stereo, the screen-audio wire format): the mic
///   *is* the source's audio in OBS — the phone as a wireless microphone.
///
/// See docs/PROTOCOL.md packet types 9 and 10.
final class AudioReference {
    enum Purpose {
        case lipSyncReference
        case playback
    }

    /// Delivers a chunk of S16LE PCM (format per `Purpose`) plus the
    /// capture time of its first sample, in the same clock domain as
    /// video frame pts.
    var onPCM: ((_ pcm: Data, _ ptsNanoseconds: UInt64) -> Void)?

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let targetFormat: AVAudioFormat
    private var timebase = mach_timebase_info_data_t()
    private var observer: NSObjectProtocol?

    init(purpose: Purpose = .lipSyncReference) {
        switch purpose {
        case .lipSyncReference:
            targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: Double(OBSCProtocol.audioSampleRate),
                channels: AVAudioChannelCount(OBSCProtocol.audioChannels),
                interleaved: true)!
        case .playback:
            // Same wire format as screen-mirror audio, so the plugin's
            // existing playback path handles it unchanged. The converter
            // upmixes the mono mic to both channels.
            targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: Double(OBSCProtocol.screenAudioSampleRate),
                channels: AVAudioChannelCount(OBSCProtocol.screenAudioChannels),
                interleaved: true)!
        }
        mach_timebase_info(&timebase)
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    static func requestPermission() async -> Bool {
        // AVAudioSession API (works on the iOS 16.2 SDK / Xcode 14.2);
        // AVAudioApplication is iOS 17+ only.
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        // Record while coexisting with the streamer's real audio setup.
        try session.setCategory(.playAndRecord, mode: .default,
                                options: [.mixWithOthers, .allowBluetooth,
                                          .defaultToSpeaker])
        try session.setActive(true)

        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else {
            throw NSError(domain: "AudioReference", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No audio input"])
        }
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) {
            [weak self] buffer, time in
            self?.process(buffer, time: time)
        }
        engine.prepare()
        try engine.start()

        // A route change (Bluetooth headset connecting, wired mic
        // unplugged) reconfigures the engine and kills the tap; without
        // this the lip-sync reference silently dies for the session.
        if observer == nil {
            observer = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange,
                object: engine, queue: .main) { [weak self] _ in
                self?.restart()
            }
        }
    }

    private func restart() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        do {
            try start()
        } catch {
            print("Audio reference restart failed: \(error.localizedDescription)")
        }
    }

    func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    private func hostTimeToNanoseconds(_ hostTime: UInt64) -> UInt64 {
        hostTime &* UInt64(timebase.numer) / UInt64(timebase.denom)
    }

    private func process(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        guard let converter, let onPCM, time.isHostTimeValid else { return }

        // pts = capture time of the first input sample. Resampling adds
        // processing delay downstream but does not move this timestamp.
        let ptsNs = hostTimeToNanoseconds(time.hostTime)

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat,
                                         frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, out.frameLength > 0,
              let channel = out.int16ChannelData else { return }

        // Interleaved target: channel[0] holds all channels' samples.
        let bytes = Int(out.frameLength)
            * Int(targetFormat.channelCount)
            * MemoryLayout<Int16>.size
        let data = Data(bytes: channel[0], count: bytes)
        onPCM(data, ptsNs)
    }
}
