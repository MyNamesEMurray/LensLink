import ReplayKit
import CoreMedia

/// ReplayKit broadcast-upload extension: captures the whole screen (video +
/// system audio) and streams it to the OBS plugin over the same wire
/// protocol the camera app uses. The plugin dials port 9979 on the device;
/// usbmuxd tunnels that over USB exactly as it does for the camera, so
/// screen mirroring works over Wi-Fi *and* USB with no plugin transport
/// change.
///
/// Everything below the sample buffers lives in `ScreenStreamPipeline`,
/// shared with the in-process ScreenCaptureKit path (`ScreenCaptureSession`)
/// that iOS 27 makes possible. This class is only the ReplayKit shell:
/// lifecycle callbacks in, sample buffers through, failures back out as
/// `finishBroadcastWithError` — an extension has no UI, so an error that
/// isn't reported that way is invisible.
///
/// ReplayKit's broadcast API is deprecated as of iOS 27 in favour of
/// ScreenCaptureKit. It is not removed, and it remains the *only* screen
/// capture path on iOS 15–26, so this stays until the deployment target
/// says otherwise.
@available(iOS, deprecated: 27.0,
           message: "iOS 27+ uses ScreenCaptureSession; this is the 15–26 path")
class SampleHandler: RPBroadcastSampleHandler {
    private let pipeline = ScreenStreamPipeline(
        frontEnd: "replaykit",
        logSubsystem: "com.exaltedpixels.LensLinkCamera.broadcast")

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        pipeline.onFatalError = { [weak self] message in
            self?.finishBroadcastWithError(NSError(
                domain: "LensLink", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message]))
        }
        pipeline.start()
    }

    override func broadcastFinished() {
        pipeline.stop()
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer,
                                      with sampleBufferType: RPSampleBufferType) {
        switch sampleBufferType {
        case .video:
            pipeline.handleVideo(sampleBuffer)
        case .audioApp:
            pipeline.handleAudio(sampleBuffer)
        case .audioMic:
            break // omitted by design (see ScreenStreamPipeline)
        @unknown default:
            break
        }
    }
}
