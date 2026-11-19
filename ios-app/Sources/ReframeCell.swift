import Foundation

final class ReframeCell: @unchecked Sendable {
    struct Window: Equatable {
        var zoom = 1.0
        var x = 0.5
        var y = 0.5
        var isActive: Bool { zoom > 1.0001 }
    }

    static let maxZoom = 4.0

    private let stored = Locked(Window())

    var window: Window {
        get { stored.value }
        set {
            let zoom = min(max(newValue.zoom, 1), Self.maxZoom)
            let half = 0.5 / zoom
            stored.value = Window(zoom: zoom,
                                  x: min(max(newValue.x, half), 1 - half),
                                  y: min(max(newValue.y, half), 1 - half))
        }
    }
}
