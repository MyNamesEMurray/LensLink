import AVFoundation
import AVKit
import UIKit

/// Keeps the camera streaming after the user leaves LensLink, by moving
/// the live picture into a Picture in Picture window.
///
/// iOS suspends camera capture for any app that isn't on screen — the
/// rule the whole remote-start design exists to work around. The one
/// sanctioned exception is multitasking camera access
/// (`AVCaptureSession.isMultitaskingCameraAccessEnabled`, set in
/// CameraManager), which iOS grants when any of these hold:
///
/// * the app runs on an iPad that supports Stage Manager with an
///   extended display — the iPad Split View / Stage Manager case, which
///   needs nothing from this file;
/// * the app links against the iOS 18 SDK or later **and** declares
///   `voip` in `UIBackgroundModes` — LensLink's iPhone route, declared
///   in `project.yml` (the reasoning, and what it costs, is written up
///   in docs/DEVELOPMENT.md);
/// * the app holds the `com.apple.developer.avfoundation.multitasking-
///   camera-access` entitlement, which is requested from Apple.
///
/// Capture only *survives* backgrounding while a PiP window is up, so
/// this controller is the mechanism, not a nicety: no PiP, no background
/// stream. And it has to be a window iOS can *see* — parked against the
/// screen edge it stops counting, capture is interrupted, and the stream
/// resumes when the window is pulled back out. That one is iOS's rule,
/// not something this code chooses.
///
/// **Sample-buffer content source, not the video-call one.** The
/// video-call flavour (`AVPictureInPictureVideoCallViewController`)
/// reads like the natural fit for a camera, and it can shape its window
/// through `preferredContentSize` — but since iOS 16 it draws no
/// controls at all, so a window once opened could only be escaped by
/// force-quitting the app. This flavour hands the display layer straight
/// to PiP and gets the standard close and restore buttons with it. The
/// trade is that the window takes its shape from the frames themselves
/// rather than from us, so it shows the stream the way OBS receives it:
/// sensor-native landscape, whichever way the phone is held.
///
/// Locking the phone ends PiP, and ends the stream with it. This buys
/// "keep streaming while I use another app", never "keep streaming with
/// the screen off".
@MainActor
final class BackgroundPiP: NSObject {
    static let shared = BackgroundPiP()

    /// The window's frames. Lives outside the main actor because the
    /// capture queue writes to it once per frame.
    private let sink = FrameSink()

    /// Whether PiP can carry the stream on this device at all: the
    /// hardware supports PiP, and the capture session was granted
    /// multitasking camera access. Both are needed — a PiP window
    /// without multitasking access shows a frozen last frame while the
    /// camera shuts down behind it.
    private(set) var isAvailable = false

    /// Whether this build and device could ever do it, ignoring the
    /// capture session: PiP hardware support. Paired with
    /// `CameraManager.supportsMultitaskingCapture` by
    /// `Streamer.backgroundStreamingAvailable`, which is what the
    /// Options toggle keys off.
    static var isPlatformSupported: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    /// The user's Options toggle.
    var isEnabled = true {
        didSet { applyAutoStart() }
    }

    /// Streaming right now: auto-start is armed only while there's a
    /// stream worth keeping alive.
    private var isStreaming = false

    private var controller: AVPictureInPictureController?
    /// Holds the display layer in the view hierarchy. PiP won't adopt a
    /// layer that isn't in a window, so the layer lives in a hairline
    /// view behind the preview rather than nowhere at all.
    private var hostView: UIView?
    private weak var sourceView: UIView?

    /// The preview the window is born from — CameraPreviewView's, handed
    /// over when it appears. A different view rebuilds the controller:
    /// the content source is fixed at construction.
    func attach(sourceView view: UIView, session: AVCaptureSession) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            isAvailable = false
            return
        }
        // Multitasking access is decided by the session's configuration,
        // so this answer is only meaningful once CameraManager has built
        // the graph — which it has by the time a preview exists.
        let multitasking: Bool
        if #available(iOS 16.0, *) {
            multitasking = session.isMultitaskingCameraAccessEnabled
        } else {
            multitasking = false
        }
        isAvailable = multitasking
        guard multitasking, sourceView !== view else { return }
        sourceView = view

        // One point in the corner: enough to be a layer in a window,
        // small enough to render nothing anyone can see. What the user
        // actually watches is the capture preview layer underneath,
        // untouched.
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        host.isUserInteractionEnabled = false
        sink.layer.frame = host.bounds
        sink.layer.videoGravity = .resizeAspect
        host.layer.addSublayer(sink.layer)
        view.addSubview(host)
        hostView = host

        let source = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: sink.layer, playbackDelegate: self)
        let controller = AVPictureInPictureController(contentSource: source)
        controller.delegate = self
        self.controller = controller
        applyAutoStart()
    }

    func detach(sourceView view: UIView) {
        guard sourceView === view else { return }
        sourceView = nil
        teardown()
    }

    /// Streaming state, from Streamer's start/stop.
    ///
    /// Stopping tears the controller down rather than just disarming it:
    /// a controller that still exists can be started by the system as the
    /// app leaves the screen, and with no stream behind it the window
    /// opens on whatever frame the layer last held — the "PiP appears
    /// frozen even though I never started a stream" report. No
    /// controller, no window; the next stream builds a fresh one when its
    /// preview appears.
    func setStreaming(_ streaming: Bool) {
        isStreaming = streaming
        if streaming {
            applyAutoStart()
            return
        }
        stop()
        // Cleared too, or `attach` would take the next stream's preview
        // for the one it already holds and never rebuild the controller.
        sourceView = nil
        teardown()
    }

    private func teardown() {
        controller?.canStartPictureInPictureAutomaticallyFromInline = false
        controller = nil
        hostView?.removeFromSuperview()
        hostView = nil
        sink.layer.removeFromSuperlayer()
        sink.isActive = false
        sink.wantsFrames = false
        sink.flush()
    }

    /// The system's own answer to "is a PiP window carrying this stream
    /// right now", which stays true while the window is stashed against
    /// the screen edge — unlike the frame flag, which follows rendering.
    var hasWindow: Bool {
        controller?.isPictureInPictureActive ?? false
    }

    /// Arms (or disarms) the system's own "start PiP when this app goes
    /// away" behaviour. Automatic start is the only correct trigger: an
    /// app can't reliably start PiP itself once it is already leaving
    /// the screen.
    ///
    /// Frames start flowing to the layer at the same moment, and *not*
    /// only once a window opens: PiP adopts a layer that is already
    /// showing something, and a layer fed nothing until the hand-off has
    /// nothing to hand over (docs/PERFORMANCE.md carries the cost note).
    private func applyAutoStart() {
        let armed = isEnabled && isStreaming
        controller?.canStartPictureInPictureAutomaticallyFromInline = armed
        sink.wantsFrames = armed && controller != nil
    }

    func stop() {
        guard let controller, controller.isPictureInPictureActive else { return }
        controller.stopPictureInPicture()
    }

    /// True while a PiP window is up. Streamer reads this to decide
    /// whether backgrounding should end the stream.
    var isActive: Bool { sink.isActive }

    /// One frame for the PiP window, called on the capture queue for
    /// every frame the encoder gets — one boolean read while background
    /// streaming is off or nothing is streaming.
    ///
    /// Same drop-don't-queue contract as the rest of the pipeline: a
    /// layer that isn't ready loses the frame rather than growing a
    /// backlog that drifts further behind the live stream every second.
    nonisolated func enqueue(_ sampleBuffer: CMSampleBuffer) {
        sink.enqueue(sampleBuffer)
    }
}

// MARK: - Playback delegate
//
// A camera has no timeline: nothing to scrub, nothing to pause to. The
// infinite time range is what tells PiP this is live, so it draws the
// live window — close and restore, no scrubber — instead of a player's
// transport controls.
extension BackgroundPiP: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController, setPlaying playing: Bool
    ) {
        // Nothing to pause: the stream is whatever the camera is doing.
    }

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(
        _ controller: AVPictureInPictureController
    ) -> CMTimeRange {
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(
        _ controller: AVPictureInPictureController
    ) -> Bool {
        false
    }

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {
        // The window sizes itself around the frames; nothing to do.
    }

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}

// MARK: - Window lifecycle

extension BackgroundPiP: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(
        _ controller: AVPictureInPictureController
    ) {
        Task { @MainActor in BackgroundPiP.shared.sink.isActive = true }
    }

    nonisolated func pictureInPictureControllerWillStopPictureInPicture(
        _ controller: AVPictureInPictureController
    ) {
        Task { @MainActor in BackgroundPiP.shared.sink.isActive = false }
    }

    /// The window went away — closed by the user, or because the app is
    /// coming back to the front. Deliberately NOT where the stream ends:
    /// the app is still running, and what actually decides whether a
    /// stream can continue is whether iOS left us the camera.
    nonisolated func pictureInPictureControllerDidStopPictureInPicture(
        _ controller: AVPictureInPictureController
    ) {
        Task { @MainActor in BackgroundPiP.shared.sink.isActive = false }
    }

    /// Tapping "return to app" on the window. LensLink is one scene with
    /// one screen, and iOS has already brought it forward by the time
    /// this runs, so there is no interface to rebuild — but the system
    /// waits on this handler before finishing the transition, and
    /// leaving it unimplemented leaves the animation hanging.
    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        Task { @MainActor in BackgroundPiP.shared.sink.isActive = false }
    }
}

/// The live picture, shared between the main actor (which builds the
/// layer and hands it to PiP) and the capture queue (which feeds it).
/// `AVSampleBufferDisplayLayer` takes enqueues from any thread.
private final class FrameSink: @unchecked Sendable {
    let layer = AVSampleBufferDisplayLayer()

    /// Written on PiP transitions, read once per captured frame.
    var isActive: Bool {
        get { lock.lock(); defer { lock.unlock() }; return active }
        set { lock.lock(); active = newValue; lock.unlock() }
    }

    /// Whether the layer should be fed at all: true for the life of a
    /// stream PiP is armed for, so the layer has something to hand over
    /// the moment the app leaves the screen.
    var wantsFrames: Bool {
        get { lock.lock(); defer { lock.unlock() }; return feeding }
        set { lock.lock(); feeding = newValue; lock.unlock() }
    }

    private var active = false
    private var feeding = false
    private let lock = NSLock()

    func enqueue(_ sampleBuffer: CMSampleBuffer) {
        guard wantsFrames else { return }
        if layer.status == .failed {
            layer.flush()
        }
        guard layer.isReadyForMoreMediaData else { return }
        // Live frames, no timebase: without this attachment the layer
        // holds each buffer until its (capture-clock) presentation time
        // arrives on a timebase that never runs, and the window stays
        // black.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let raw = CFArrayGetValueAtIndex(attachments, 0)
            let dictionary = unsafeBitCast(raw, to: CFMutableDictionary.self)
            CFDictionarySetValue(
                dictionary,
                Unmanaged.passUnretained(
                    kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        layer.enqueue(sampleBuffer)
    }

    func flush() {
        layer.flush()
    }
}
