import ReplayKit
import CoreMedia

/// ReplayKit broadcast-upload extension: captures the whole screen (video +
/// system audio) and streams it to the OBS plugin over the same wire
/// protocol the camera app uses. The plugin dials port 9979 on the device;
/// usbmuxd tunnels that over USB exactly as it does for the camera, so
/// screen mirroring works over Wi-Fi *and* USB with no plugin transport
/// change. The pipeline itself is ScreenStreamPipeline.
///
/// System audio only (no microphone) by design: a streamer already has
/// their real mic in OBS, so sending the phone mic would double it. See
/// docs/PROTOCOL.md.
class SampleHandler: RPBroadcastSampleHandler {
    private let pipeline = ScreenStreamPipeline(
        logSubsystem: "com.exaltedpixels.LensLinkCamera.broadcast")

    /// Extensions have no UI, so failures here are invisible unless we end
    /// the broadcast with a descriptive error (iOS shows it as an alert).
    private func fail(_ message: String) {
        finishBroadcastWithError(NSError(
            domain: "LensLink", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]))
    }

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        pipeline.onFatalError = { [weak self] message in
            self?.fail(message)
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
            break // omitted by design (see class note)
        @unknown default:
            break
        }
    }
}
