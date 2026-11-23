import Foundation

var failures = 0

func check(_ condition: Bool, _ name: String) {
    if !condition {
        failures += 1
        print("FAIL: \(name)")
    }
}

func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

let cell = ReframeCell()
check(!cell.window.isActive, "default window inactive")

cell.window = ReframeCell.Window(zoom: 0.5, x: 0.5, y: 0.5)
check(near(cell.window.zoom, 1), "zoom below 1 clamps to 1")
check(!cell.window.isActive, "window inactive at zoom 1")

cell.window = ReframeCell.Window(zoom: 9, x: 0.5, y: 0.5)
check(near(cell.window.zoom, 4), "zoom above 4 clamps to 4")
check(cell.window.isActive, "window active at zoom 4")

cell.window = ReframeCell.Window(zoom: 2, x: 0, y: 1)
check(near(cell.window.x, 0.25) && near(cell.window.y, 0.75),
      "centre clamped so a 2x window stays inside")

cell.window = ReframeCell.Window(zoom: 4, x: 5, y: -5)
check(near(cell.window.x, 0.875) && near(cell.window.y, 0.125),
      "centre clamped so a 4x window stays inside")

cell.window = ReframeCell.Window(zoom: 1, x: 0.1, y: 0.9)
check(near(cell.window.x, 0.5) && near(cell.window.y, 0.5),
      "centre forced to the middle at zoom 1")

if failures == 0 {
    print("PASS: ReframeCell clamping")
} else {
    exit(1)
}
