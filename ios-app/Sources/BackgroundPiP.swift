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
/// this controller is the mechanism, not a nicety: no PiP, no
/// background stream. Everything here is inert where the platform says
/// no (`isAvailable` false), and the frame path costs nothing until a
/// window actually opens — `enqueue` returns on one boolean read while
/// the app is inline.
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

    /// The capture dimensions, from Streamer. PiP sizes its window from
    /// the content controller's `preferredContentSize`, and without one
    /// it guesses from the source view — a portrait phone screen — so a
    /// landscape stream arrived letterboxed inside a portrait box and
    /// read as "rotated" next to the app's own upright preview. Setting
    /// the real dimensions makes the window the shape of the picture,
    /// which is the shape OBS receives.
    var videoSize: CGSize = CGSize(width: 16, height: 9) {
        didSet {
            guard videoSize != oldValue else { return }
            callViewController?.preferredContentSize = videoSize
        }
    }

    private var controller: AVPictureInPictureController?
    private var callViewController: SampleBufferCallViewController?
    private weak var sourceView: UIView?

    /// The inline view PiP flies out of — CameraPreviewView's, handed
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

        let content = SampleBufferCallViewController(sink: sink)
        content.preferredContentSize = videoSize
        let source = AVPictureInPictureController.ContentSource(
            activeVideoCallSourceView: view,
            contentViewController: content)
        let controller = AVPictureInPictureController(contentSource: source)
        controller.delegate = self
        // Deliberately NOT requiresLinearPlayback: it reads like the
        // honest choice for a live camera (no scrubbing to offer), but it
        // takes the window's controls away with it — including the close
        // and restore buttons, leaving no way out of PiP but force-
        // quitting the app.
        callViewController = content
        self.controller = controller
        applyAutoStart()
    }

    func detach(sourceView view: UIView) {
        guard sourceView === view else { return }
        sourceView = nil
        controller = nil
        callViewController = nil
        sink.isActive = false
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
        controller?.canStartPictureInPictureAutomaticallyFromInline = false
        controller = nil
        callViewController = nil
        // Cleared too, or `attach` would take the next stream's preview
        // for the one it already holds and never rebuild the controller.
        sourceView = nil
        sink.isActive = false
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
    private func applyAutoStart() {
        controller?.canStartPictureInPictureAutomaticallyFromInline =
            isEnabled && isStreaming
    }

    func stop() {
        guard let controller, controller.isPictureInPictureActive else { return }
        controller.stopPictureInPicture()
    }

    /// True while a PiP window is up. Streamer reads this to decide
    /// whether backgrounding should end the stream.
    var isActive: Bool { sink.isActive }

    /// One frame for the PiP window, called on the capture queue for
    /// every frame the encoder gets. Costs a boolean read while inline;
    /// the display layer only ever sees frames once a window is open.
    ///
    /// Same drop-don't-queue contract as the rest of the pipeline: a
    /// layer that isn't ready loses the frame rather than growing a
    /// backlog that drifts further behind the live stream every second.
    nonisolated func enqueue(_ sampleBuffer: CMSampleBuffer) {
        sink.enqueue(sampleBuffer)
    }
}

extension BackgroundPiP: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(
        _ controller: AVPictureInPictureController
    ) {
        Task { @MainActor in BackgroundPiP.shared.sink.isActive = true }
    }

    nonisolated func pictureInPictureControllerWillStopPictureInPicture(
        _ controller: AVPictureInPictureController
    ) {
        Task { @MainActor in
            let pip = BackgroundPiP.shared
            pip.sink.isActive = false
            pip.sink.flush()
        }
    }

    /// The window went away — closed by the user, or because the app is
    /// coming back to the front. Deliberately NOT where the stream ends:
    /// the app is still running, and the thing that actually decides
    /// whether a stream can continue is whether iOS left us the camera.
    /// Streamer watches for that (a capture interruption with no window
    /// up), which keeps a stashed window — hidden at the screen edge, but
    /// still a window — from being mistaken for a dismissal.
    nonisolated func pictureInPictureControllerDidStopPictureInPicture(
        _ controller: AVPictureInPictureController
    ) {
        Task { @MainActor in
            let pip = BackgroundPiP.shared
            pip.sink.isActive = false
            pip.sink.flush()
        }
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

/// The live picture, shared between the main actor (which builds and
/// lays out the layer) and the capture queue (which feeds it). The
/// layer itself is the only mutable state, and `AVSampleBufferDisplayLayer`
/// takes enqueues from any thread.
private final class FrameSink: @unchecked Sendable {
    let layer = AVSampleBufferDisplayLayer()

    /// Written on PiP transitions, read once per captured frame.
    var isActive: Bool {
        get { lock.lock(); defer { lock.unlock() }; return active }
        set { lock.lock(); active = newValue; lock.unlock() }
    }
    private var active = false
    private let lock = NSLock()

    func enqueue(_ sampleBuffer: CMSampleBuffer) {
        guard isActive else { return }
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

/// The PiP window's content: the sink's layer, fed the same frames the
/// encoder sends to OBS, so what's in the little window is what's on the
/// wire (green screen and all) rather than a second capture path.
private final class SampleBufferCallViewController:
    AVPictureInPictureVideoCallViewController {

    private let sink: FrameSink

    init(sink: FrameSink) {
        self.sink = sink
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used — this controller is code-only")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        sink.layer.videoGravity = .resizeAspect
        view.layer.addSublayer(sink.layer)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // The window resizes as the user drags it between corners; no
        // implicit animation, or every resize smears the live picture.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sink.layer.frame = view.bounds
        CATransaction.commit()
    }
}
