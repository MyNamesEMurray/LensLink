import SwiftUI
import AVFoundation

/// Live camera preview backed by AVCaptureVideoPreviewLayer, with optional
/// tap-to-focus (reports the tap in device coordinates) and pinch-to-zoom.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    /// The camera's session queue. Attaching/detaching the preview layer
    /// takes the session's internal lock; doing it on the main thread while
    /// `stopRunning()` (1–3 s) holds that lock on the session queue freezes
    /// the whole UI — the classic "app hangs for a few seconds after
    /// stopping the stream". Routing both through the session queue
    /// serializes them after any start/stop instead of blocking main.
    let sessionQueue: DispatchQueue
    /// The camera the session is currently running, for the rotation
    /// coordinator (iOS 17+). Changing it re-targets the coordinator; nil
    /// stops rotation tracking.
    var device: AVCaptureDevice?
    var videoGravity: AVLayerVideoGravity = .resizeAspect
    /// While false, the preview layer's connection is disabled so frames
    /// stop being rendered to it. Used by the dim overlay: without this,
    /// the GPU keeps compositing a full-rate preview under a near-black
    /// cover for as long as the phone sits dimmed — pure wasted power.
    /// Capture (and the outgoing stream) is unaffected.
    var previewEnabled: Bool = true
    var onTapAtDevicePoint: ((CGPoint) -> Void)?
    var onPinchZoom: ((_ phase: PinchPhase, _ scale: CGFloat) -> Void)?

    enum PinchPhase {
        case began
        case changed
        case ended
    }

    final class PreviewView: UIView {
        override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        /// The camera's session queue (same lock discipline as attach —
        /// see the `sessionQueue` note on CameraPreviewView).
        var sessionQueue: DispatchQueue?
        /// The device the coordinator is currently tracking, so a SwiftUI
        /// update that changed something else doesn't rebuild it. Weak: a
        /// retired camera must not be kept alive by this bookkeeping.
        private weak var trackedDevice: AVCaptureDevice?

        /// Re-targets rotation tracking only when the camera actually
        /// changed (lens switch, session rebuild).
        func trackRotation(of device: AVCaptureDevice?) {
            guard device !== trackedDevice else { return }
            trackedDevice = device
            if device == nil {
                stopRotationTracking()
            } else {
                startRotationTracking(device: device)
            }
        }

        /// `AVCaptureDevice.RotationCoordinator` (iOS 17+), held as
        /// `AnyObject` because a stored property can't carry an
        /// availability-gated type. Nil below iOS 17, where
        /// `syncPreviewOrientation()` does the job instead.
        private var rotationCoordinator: AnyObject?
        private var rotationObservation: NSKeyValueObservation?

        // Rotation reaches a view as a re-layout, so this is the hook that
        // keeps the preview fullscreen through every UI orientation on the
        // pre-iOS 17 path. From 17 the coordinator drives it instead, and
        // this becomes a no-op.
        override func layoutSubviews() {
            super.layoutSubviews()
            syncPreviewOrientation()
        }

        /// Starts (or restarts) the rotation coordinator for `device`.
        ///
        /// Apple's replacement for the deprecated `videoOrientation`, and
        /// the only correct one: the angle a device reports for a given
        /// physical orientation is *not* uniform across models, so mapping
        /// `interfaceOrientation` to degrees by hand is exactly the bug
        /// this class exists to prevent. It also re-reports when the app
        /// moves between displays, which is what keeps the preview upright
        /// on iPhone Duo as the device is opened and closed.
        ///
        /// `…ForHorizonLevelPreview` is the preview-layer angle (level
        /// relative to gravity); the capture path is deliberately *not*
        /// driven from here — the stream stays sensor-native landscape.
        func startRotationTracking(device: AVCaptureDevice?) {
            guard #available(iOS 17.0, *) else { return }
            rotationObservation = nil
            rotationCoordinator = nil
            guard let device else { return }
            let coordinator = AVCaptureDevice.RotationCoordinator(
                device: device, previewLayer: previewLayer)
            rotationCoordinator = coordinator
            apply(rotationAngle: coordinator.videoRotationAngleForHorizonLevelPreview)
            // KVO rather than a notification: the coordinator publishes the
            // angle as an observable property, and it changes on every
            // physical rotation and display move.
            rotationObservation = coordinator.observe(
                \.videoRotationAngleForHorizonLevelPreview,
                options: [.new]) { [weak self] _, change in
                    guard let angle = change.newValue else { return }
                    DispatchQueue.main.async {
                        self?.apply(rotationAngle: angle)
                    }
                }
        }

        func stopRotationTracking() {
            rotationObservation = nil
            rotationCoordinator = nil
        }

        @available(iOS 17.0, *)
        private func apply(rotationAngle angle: CGFloat) {
            let layer = previewLayer
            // Off-main like every other connection touch here: the
            // connection only exists after the queued attach has run, and
            // writing it shouldn't contend with a start/stop holding the
            // session lock.
            sessionQueue?.async {
                guard let connection = layer.connection,
                      connection.isVideoRotationAngleSupported(angle),
                      connection.videoRotationAngle != angle else { return }
                connection.videoRotationAngle = angle
            }
        }

        /// Keeps the preview upright in whatever orientation the UI is in.
        /// The preview layer's connection orientation is independent of the
        /// capture output's: the *stream* stays sensor-native landscape,
        /// while the *preview* renders for the screen the user is holding —
        /// rotate the phone and the live view stays fullscreen and upright
        /// instead of going sideways.
        ///
        /// iOS 15/16 only. `videoOrientation` is deprecated from iOS 17,
        /// where `startRotationTracking(device:)` owns this instead.
        func syncPreviewOrientation() {
            if #available(iOS 17.0, *) { return }
            guard let scene = window?.windowScene else { return }
            let video: AVCaptureVideoOrientation
            switch scene.interfaceOrientation {
            case .portrait: video = .portrait
            case .portraitUpsideDown: video = .portraitUpsideDown
            case .landscapeLeft: video = .landscapeLeft
            case .landscapeRight: video = .landscapeRight
            default: return
            }
            let layer = previewLayer
            sessionQueue?.async {
                if let connection = layer.connection,
                   connection.isVideoOrientationSupported,
                   connection.videoOrientation != video {
                    connection.videoOrientation = video
                }
            }
        }
    }

    final class Coordinator: NSObject {
        var parent: CameraPreviewView

        init(parent: CameraPreviewView) {
            self.parent = parent
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let view = recognizer.view as? PreviewView else { return }
            let layerPoint = recognizer.location(in: view)
            let devicePoint = view.previewLayer
                .captureDevicePointConverted(fromLayerPoint: layerPoint)
            parent.onTapAtDevicePoint?(devicePoint)
        }

        @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            let phase: PinchPhase
            switch recognizer.state {
            case .began:
                phase = .began
            case .ended, .cancelled, .failed:
                phase = .ended
            default:
                phase = .changed
            }
            parent.onPinchZoom?(phase, recognizer.scale)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.sessionQueue = sessionQueue
        let layer = view.previewLayer
        layer.videoGravity = videoGravity
        // Off-main attach (see `sessionQueue` note). The preview stays
        // blank until the session is running anyway, so deferring the
        // attach behind a pending startRunning() costs nothing visible.
        let session = session
        sessionQueue.async {
            layer.session = session
        }
        // The attach above creates the connection after any layout has
        // already run; sync once behind it so the first frame renders in
        // the current UI orientation (main hop: windowScene is UI state).
        sessionQueue.async {
            DispatchQueue.main.async { [weak view] in
                view?.syncPreviewOrientation()
            }
        }
        view.trackRotation(of: device)

        if onTapAtDevicePoint != nil {
            let tap = UITapGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.handleTap(_:)))
            view.addGestureRecognizer(tap)
        }
        if onPinchZoom != nil {
            let pinch = UIPinchGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.handlePinch(_:)))
            view.addGestureRecognizer(pinch)
        }
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        context.coordinator.parent = self
        uiView.previewLayer.videoGravity = videoGravity
        uiView.trackRotation(of: device)

        // Off-main like attach/detach: the connection exists only after the
        // queued attach above has run, and toggling it shouldn't contend
        // with a start/stop holding the session lock.
        let layer = uiView.previewLayer
        let enabled = previewEnabled
        sessionQueue.async {
            if let connection = layer.connection,
               connection.isEnabled != enabled {
                connection.isEnabled = enabled
            }
        }
    }

    static func dismantleUIView(_ uiView: PreviewView, coordinator: Coordinator) {
        // Off-main detach: when the streaming view closes right as
        // stopRunning() executes, detaching here on the main thread would
        // block until the stop completes (the 2–5 s hang). The queue hop
        // retains the layer until the detach has actually run.
        uiView.stopRotationTracking()
        let layer = uiView.previewLayer
        coordinator.parent.sessionQueue.async {
            layer.session = nil
        }
    }
}
