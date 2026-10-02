#if DEBUG
import AVFoundation
import UIKit

enum ScreenshotStage {
    enum Shot: String {
        case home
        case liveGlance = "live-glance"
        case liveTray = "live-tray"
        case format
        case options
    }

    static let argument = "-LensLinkScreenshots"

    static let shot: Shot? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: argument),
              arguments.indices.contains(index + 1) else { return nil }
        return Shot(rawValue: arguments[index + 1])
    }()

    static var isActive: Bool { shot != nil }

    static var isLive: Bool { shot == .liveGlance || shot == .liveTray }

    static let scene: UIImage? = {
        guard let path = ProcessInfo.processInfo
            .environment["LENSLINK_SCREENSHOT_SCENE"] else { return nil }
        return UIImage(contentsOfFile: path)
    }()

    static let obsHost = "Studio Mac"
    static let obsVersion = "32.0.1"

    static let lenses: [CameraManager.Lens] = [
        CameraManager.defaultLens,
        CameraManager.Lens(deviceType: .builtInUltraWideCamera,
                           position: .back, label: "Ultra Wide (0.5×)"),
        CameraManager.Lens(deviceType: .builtInTelephotoCamera,
                           position: .back, label: "Telephoto"),
        CameraManager.Lens(deviceType: .builtInWideAngleCamera,
                           position: .front, label: "Front"),
    ]

    static func zoomFactor(_ lens: CameraManager.Lens) -> Double {
        guard lens.position == .back else { return 1 }
        switch lens.deviceType {
        case .builtInUltraWideCamera: return 0.5
        case .builtInTelephotoCamera: return 4
        default: return 1
        }
    }

    static func registerDefaults() {
        guard isActive else { return }
        UserDefaults.standard.register(defaults: [
            "resolution": CameraManager.Resolution.uhd4k.rawValue,
            "fps": 60,
            "videoCodec": VideoCodec.hevc.rawValue,
            "streamColor": StreamColor.hlg.rawValue,
            "streamQuality": Streamer.StreamQuality.maximum.rawValue,
            "idleAppearance": Streamer.IdleAppearance.standard.rawValue,
            "sendAudioReference": true,
            "showConnectionHelp": false,
        ])
    }
}
#endif
