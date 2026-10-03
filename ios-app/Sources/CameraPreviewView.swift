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
    var videoGravity: AVLayerVideoGravity = .resizeAspect
    /// While false, the preview layer's connection is disabled so frames
    /// stop being rendered to it. Used by the dim overlay: without this,
    /// the GPU keeps compositing a full-rate preview under a near-black
    /// cover for as long as the phone sits dimmed — pure wasted power.
    /// Capture (and the outgoing stream) is unaffected.
    var previewEnabled: Bool = true
    /// Tap: focus/expose here. Reports the point in device coordinates
    /// (0…1, for the camera) and in this view's coordinates (for the
    /// marker drawn where the finger was).
    var onTapAtDevicePoint: ((_ devicePoint: CGPoint, _ viewPoint: CGPoint) -> Void)?
    /// Long press: lock focus and exposure here — the Camera app's
    /// AE/AF Lock. Same two points as the tap.
    var onLongPressAtDevicePoint: ((_ devicePoint: CGPoint, _ viewPoint: CGPoint) -> Void)?
    var onPinchZoom: ((_ phase: PinchPhase, _ scale: CGFloat) -> Void)?
    /// One-finger vertical drag — the Camera app's sun slider, used for
    /// exposure bias. `travel` is the drag's distance as a fraction of the
    /// view's height, positive upwards, measured from where it began.
    var onVerticalDrag: ((_ phase: PinchPhase, _ travel: CGFloat) -> Void)?

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

        // Rotation reaches a view as a re-layout, so this is the hook that
        // keeps the preview fullscreen through every UI orientation.
        override func layoutSubviews() {
            super.layoutSubviews()
            syncPreviewOrientation()
        }

        /// Keeps the preview upright in whatever orientation the UI is in.
        /// The preview layer's connection orientation is independent of the
        /// capture output's: the *stream* stays sensor-native landscape,
        /// while the *preview* renders for the screen the user is holding —
        /// rotate the phone and the live view stays fullscreen and upright
        /// instead of going sideways.
        func syncPreviewOrientation() {
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
            parent.onTapAtDevicePoint?(devicePoint, layerPoint)
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began,
                  let view = recognizer.view as? PreviewView else { return }
            let layerPoint = recognizer.location(in: view)
            let devicePoint = view.previewLayer
                .captureDevicePointConverted(fromLayerPoint: layerPoint)
            parent.onLongPressAtDevicePoint?(devicePoint, layerPoint)
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

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let view = recognizer.view else { return }
            let phase: PinchPhase
            switch recognizer.state {
            case .began:
                phase = .began
            case .ended, .cancelled, .failed:
                phase = .ended
            default:
                phase = .changed
            }
            let height = max(view.bounds.height, 1)
            parent.onVerticalDrag?(
                phase, -recognizer.translation(in: view).y / height)
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
        if onLongPressAtDevicePoint != nil {
            let press = UILongPressGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.handleLongPress(_:)))
            press.minimumPressDuration = 0.5
            view.addGestureRecognizer(press)
        }
        if onVerticalDrag != nil {
            let pan = UIPanGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.handlePan(_:)))
            // One finger only, so a pinch is never half-read as a drag.
            pan.maximumNumberOfTouches = 1
            view.addGestureRecognizer(pan)
        }
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        context.coordinator.parent = self
        uiView.previewLayer.videoGravity = videoGravity

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
        let layer = uiView.previewLayer
        coordinator.parent.sessionQueue.async {
            layer.session = nil
        }
    }
}
