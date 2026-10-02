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
                .environment["LENSLINK_SCREENSHOT_SCENE"],
              let image = UIImage(contentsOfFile: path) else { return nil }
        guard let cgImage = image.cgImage else { return image }
        let height = CGFloat(cgImage.height)
        let width = min(CGFloat(cgImage.width), height * 9 / 16)
        let crop = CGRect(x: (CGFloat(cgImage.width) - width) / 2, y: 0,
                          width: width, height: height).integral
        guard let cropped = cgImage.cropping(to: crop) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale,
                       orientation: image.imageOrientation)
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
        switch lens.label {
        case "Ultra Wide (0.5×)": return 0.5
        case "Telephoto": return 4
        default: return 1
        }
    }

    static var lensFactors: [String: Double] {
        guard isActive else { return [:] }
        return Dictionary(uniqueKeysWithValues:
            lenses.map { ($0.id, zoomFactor($0)) })
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
