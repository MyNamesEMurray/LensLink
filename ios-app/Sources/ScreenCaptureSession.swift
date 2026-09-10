import Foundation
import CoreMedia
#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
#endif

/// In-process screen mirroring on iOS 27+, via ScreenCaptureKit.
///
/// iOS 27 brought ScreenCaptureKit to iPhone and iPad and deprecated the
/// ReplayKit broadcast API in the same release. The replacement is not
/// just a renamed one: it captures the display **in this process**, so
/// there is no broadcast-upload extension, no second copy of the encoder
/// in a memory-capped process, and no cross-process hand-off of port 9979.
/// The `screen-capture` background mode keeps the capture running while
/// the person is in the app they actually want to mirror.
///
/// Below iOS 27 this reports `isSupported == false` and the ReplayKit
/// extension (`SampleHandler`) remains the only path — it is not going
/// anywhere while the deployment target is iOS 15.
///
/// The façade is deliberately free of `#if`: the SDK that ships with
/// Xcode 26 has no ScreenCaptureKit for iOS, so the implementation behind
/// it compiles away entirely there while every call site keeps building.
@MainActor
final class ScreenCaptureController: ObservableObject {
    static let shared = ScreenCaptureController()

    /// Whether this build and this OS can capture the screen in-process.
    /// False on iOS 15–26, and false in any build made with an SDK that
    /// predates ScreenCaptureKit on iOS.
    nonisolated static var isSupported: Bool {
        #if canImport(ScreenCaptureKit)
        if #available(iOS 27.0, *) { return true }
        return false
        #else
        return false
        #endif
    }

    /// True from the moment a stream starts until it stops or fails.
    @Published private(set) var isCapturing = false
    /// The last failure, phrased for the person. Cleared when a new
    /// capture starts.
    @Published private(set) var lastError: String?

    private var engine: AnyObject?

    /// Shows the system content-sharing picker. Capture starts when the
    /// person chooses what to share, not when this returns — everything
    /// after the picker happens in the observer callbacks.
    func presentPicker() {
        lastError = nil
        #if canImport(ScreenCaptureKit)
        if #available(iOS 27.0, *) {
            let engine = (self.engine as? Engine) ?? Engine(owner: self)
            self.engine = engine
            engine.presentPicker()
            return
        }
        #endif
        lastError = "Screen mirroring in the app needs iOS 27. "
            + "Use the screen broadcast button instead."
    }

    func stop() {
        #if canImport(ScreenCaptureKit)
        if #available(iOS 27.0, *), let engine = engine as? Engine {
            engine.stop()
        }
        #endif
        engine = nil
        isCapturing = false
    }

    fileprivate func report(capturing: Bool) {
        isCapturing = capturing
    }

    fileprivate func report(error: String) {
        lastError = error
        isCapturing = false
    }
}

#if canImport(ScreenCaptureKit)
/// The ScreenCaptureKit half: picker → filter → stream → sample buffers,
/// handed straight to the same `ScreenStreamPipeline` the ReplayKit
/// extension uses, so the wire protocol, encoder, audio conversion and
/// diagnostics are literally the same code on both paths.
@available(iOS 27.0, *)
private final class Engine: NSObject, SCContentSharingPickerObserver,
                            SCStreamOutput, SCStreamDelegate {
    private weak var owner: ScreenCaptureController?
    private let pipeline = ScreenStreamPipeline(
        frontEnd: "screencapturekit",
        logSubsystem: "com.exaltedpixels.LensLinkCamera")
    private var stream: SCStream?
    /// Sample buffers land here, off the main thread: encoding a 60 fps
    /// screen on main would fight the UI it is capturing.
    private let outputQueue = DispatchQueue(label: "obscam.screencapture",
                                            qos: .userInitiated)
    private var observing = false

    init(owner: ScreenCaptureController) {
        self.owner = owner
        super.init()
        pipeline.onFatalError = { [weak self] message in
            Task { @MainActor [weak self] in
                self?.owner?.report(error: message)
                self?.stop()
            }
        }
    }

    func presentPicker() {
        let picker = SCContentSharingPicker.shared
        if !observing {
            picker.add(self)
            observing = true
        }
        picker.isActive = true
        var configuration = SCContentSharingPickerConfiguration()
        // No microphone control: LensLink Screen sends system audio only,
        // by design — the streamer's real mic is already in OBS, and
        // offering a toggle that we then ignore would be a lie.
        configuration.showsMicrophoneControl = false
        configuration.showsCameraControl = false
        picker.defaultConfiguration = configuration
        picker.present()
    }

    func stop() {
        let picker = SCContentSharingPicker.shared
        if observing {
            picker.remove(self)
            observing = false
        }
        picker.isActive = false
        if let stream {
            stream.stopCapture { _ in }
        }
        stream = nil
        pipeline.stop()
    }

    // MARK: - Picker

    func contentSharingPicker(_ picker: SCContentSharingPicker,
                              didUpdateWith filter: SCContentFilter,
                              for stream: SCStream?) {
        Task { @MainActor [weak self] in
            self?.start(with: filter)
        }
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker,
                              didCancelFor stream: SCStream?) {
        // Nothing to clean up: the pipeline only starts once a filter
        // arrives, so a cancelled picker leaves no listener behind.
    }

    func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor [weak self] in
            self?.owner?.report(
                error: "Could not start screen capture: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func start(with filter: SCContentFilter) {
        let configuration = SCStreamConfiguration()
        // Pixel dimensions of what the person picked. `contentRect` is in
        // points; `pointPixelScale` turns it into the backing pixels the
        // encoder has to be sized for. Rounded down to even numbers —
        // H.264/HEVC chroma is subsampled, and an odd dimension is
        // rejected outright by the encoder.
        let rect = filter.contentRect
        let scale = CGFloat(filter.pointPixelScale)
        let pixelWidth = Int((rect.width * scale).rounded(.down)) & ~1
        let pixelHeight = Int((rect.height * scale).rounded(.down)) & ~1
        if pixelWidth > 0 && pixelHeight > 0 {
            configuration.width = pixelWidth
            configuration.height = pixelHeight
        }
        // System audio, same as the ReplayKit path: the pipeline converts
        // whatever arrives to the protocol's 48 kHz stereo int16.
        configuration.capturesAudio = true
        configuration.sampleRate = Int(OBSCProtocol.screenAudioSampleRate)
        configuration.channelCount = Int(OBSCProtocol.screenAudioChannels)

        let newStream = SCStream(filter: filter, configuration: configuration,
                                 delegate: self)
        do {
            try newStream.addStreamOutput(self, type: .screen,
                                          sampleHandlerQueue: outputQueue)
            try newStream.addStreamOutput(self, type: .audio,
                                          sampleHandlerQueue: outputQueue)
        } catch {
            owner?.report(
                error: "Could not attach the screen capture outputs: "
                    + error.localizedDescription)
            return
        }
        stream = newStream
        // The listener has to be up before frames start arriving, and its
        // port may still be held by the app's own standby listener — the
        // pipeline retries the bind for exactly that hand-off.
        pipeline.start()
        newStream.startCapture { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    self.owner?.report(
                        error: "Screen capture did not start: \(error.localizedDescription)")
                    self.stop()
                } else {
                    self.owner?.report(capturing: true)
                }
            }
        }
    }

    // MARK: - Stream output

    func stream(_ stream: SCStream,
                    didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                    of type: SCStreamOutputType) {
        switch type {
        case .screen:
            pipeline.handleVideo(sampleBuffer)
        case .audio:
            pipeline.handleAudio(sampleBuffer)
        default:
            // .microphone is never attached (system audio only, by design).
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.owner?.report(
                error: "Screen capture stopped: \(error.localizedDescription)")
            self.stop()
        }
    }
}
#endif
