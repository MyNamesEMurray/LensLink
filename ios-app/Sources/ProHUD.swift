import SwiftUI

/// The Pro interface (Options → Pro interface): the Live screen's
/// cinema-camera layout, for operators who want every value on screen at
/// once. Every exposure value sits in one strip across the top; tapping
/// one opens its dial under the strip. Scopes and stream health run along
/// the bottom, and the monitoring tools sit either side of Stop. It
/// replaces the standard controls only: the preview, its gestures, the
/// tally border and the idle view are StreamingView's, unchanged.
struct ProHUD: View {
    @EnvironmentObject private var streamer: Streamer
    @ObservedObject var scope: MonitorScope
    @ObservedObject private var battery = BatteryMonitor.shared
    /// Restarts StreamingView's idle fuse.
    let touched: () -> Void

    enum Param: CaseIterable {
        case lens, fps, shutter, iso, whiteBalance, tint, exposure, focus
    }

    @State private var open: Param?
    /// What auto is doing right now, polled while this view is up.
    @State private var live: CameraManager.LiveValues?
    @State private var thermal = ProcessInfo.processInfo.thermalState

    private static let mono = Font.system(.subheadline, design: .monospaced)
        .weight(.semibold)
    private static let label = Font.system(size: 10, weight: .semibold)

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: Theme.Space.s) {
                topBar
                strip
                if let open = open {
                    dial(open)
                        .padding(Theme.Space.m)
                        .background(Theme.glassPanel)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.chip,
                                                    style: .continuous))
                }
            }
            .padding(Theme.Space.s)
            .background(Color.black.opacity(0.6).ignoresSafeArea(edges: .top))
            Spacer()
            VStack(spacing: Theme.Space.s) {
                scopes
                toolRow
            }
            .padding(Theme.Space.s)
            .background(Color.black.opacity(0.6).ignoresSafeArea(edges: .bottom))
        }
        .foregroundColor(Theme.textPrimary)
        .task {
            while !Task.isCancelled {
                live = streamer.camera.liveValues
                thermal = ProcessInfo.processInfo.thermalState
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.xs) {
                Circle().fill(streamer.status.tint).frame(width: 8, height: 8)
                Text(streamer.status.displayName)
                    .font(.caption.bold())
                    .lineLimit(1)
            }
            .glassPill()
            .accessibilityElement(children: .combine)
            linkGrid
            Text(formatLabel)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Theme.textSecondary, lineWidth: 1))
            moreMenu
        }
    }

    /// The stats an operator glances at mid-stream, where a timecode
    /// would sit on a cinema camera.
    private var linkGrid: some View {
        let health = streamer.health
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Space.s),
                                   GridItem(.flexible())], spacing: 1) {
            linkRow(streamer.obsTransport == "usb" ? "USB" : "Wi-Fi",
                    health.map { String(format: "%.1f Mb/s", $0.megabitsPerSecond) } ?? "–")
            linkRow("FPS", health.map { "\($0.fps)" } ?? "–")
            linkRow(L("Dropped"), health.map { String($0.droppedFrames) } ?? "–")
            linkRow(L("Battery"), battery.percent.map { L("%lld%%", $0) } ?? "–")
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var formatLabel: String {
        let color: String
        switch streamer.activeColor {
        case .sdr: color = ""
        case .hlg: color = " HLG"
        case .log: color = " LOG"
        }
        return "\(streamer.resolution.rawValue) \(streamer.codec == .hevc ? "HEVC" : "H.264")\(color)"
    }

    private var moreMenu: some View {
        SteadyMenu(key: [streamer.isPaused, streamer.pauseReason == .user]) {
            if !streamer.isPaused || streamer.pauseReason == .user {
                Button {
                    touched()
                    streamer.setPaused(!streamer.isPaused, reason: .user)
                } label: {
                    Label(streamer.isPaused ? L("Resume") : L("Pause"),
                          systemImage: streamer.isPaused ? "play.fill" : "pause.fill")
                }
            }
            Button {
                streamer.proInterface = false
            } label: {
                Label(L("Standard interface"), systemImage: "rectangle.on.rectangle")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .frame(width: Theme.controlButton, height: Theme.controlButton)
                .contentShape(Rectangle())
        }
        .equatable()
        .accessibilityLabel(L("More"))
    }

    // MARK: - Value strip

    private var params: [Param] {
        Param.allCases.filter {
            switch $0 {
            case .iso, .shutter: return streamer.camera.supportsManualExposure
            case .whiteBalance, .tint: return streamer.camera.supportsWhiteBalanceLock
            default: return true
            }
        }
    }

    private var strip: some View {
        HStack(spacing: 0) {
            ForEach(params, id: \.self) { param in
                cell(param)
            }
        }
    }

    private func cell(_ param: Param) -> some View {
        let selected = open == param
        return Button {
            touched()
            open = selected ? nil : param
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 3) {
                    Text(title(param))
                        .font(Self.label)
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    badge(param)
                }
                Text(value(param))
                    .font(Self.mono)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 3)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: Theme.controlButton, alignment: .leading)
            .background(selected ? Theme.glassChip : Color.clear)
            .overlay(alignment: .bottom) {
                if selected {
                    Rectangle().fill(Theme.accent).frame(height: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: cellLabel(param)))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func cellLabel(_ param: Param) -> String {
        let label = [title(param), value(param)].joined(separator: ", ")
        return isAuto(param) == true ? [label, L("Auto")].joined(separator: ", ") : label
    }

    @ViewBuilder private func badge(_ param: Param) -> some View {
        if isAuto(param) == true {
            Text("A")
                .font(.system(size: 8, weight: .heavy))
                .foregroundColor(.white)
                .padding(.horizontal, 3)
                .background(Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .accessibilityHidden(true)
        }
    }

    private func title(_ param: Param) -> String {
        switch param {
        case .lens: return L("Lens")
        case .fps: return "FPS"
        case .shutter: return L("Shutter")
        case .iso: return "ISO"
        case .whiteBalance: return L("WB")
        case .tint: return L("Tint")
        case .exposure: return "EV"
        case .focus: return L("Focus")
        }
    }

    private func lockTarget(_ param: Param) -> Streamer.LockTarget? {
        switch param {
        case .shutter: return .shutter
        case .iso: return .iso
        case .whiteBalance, .tint: return .whiteBalance
        case .focus: return .focus
        default: return nil
        }
    }

    /// nil for values that have no auto (lens, frame rate, EV).
    private func isAuto(_ param: Param) -> Bool? {
        lockTarget(param).map { !streamer.isLocked($0) }
    }

    private func value(_ param: Param) -> String {
        let auto = isAuto(param) == true
        switch param {
        case .lens:
            return Self.factorLabel(lensFactor * Double(streamer.zoom)) + "×"
        case .fps:
            return "\(streamer.fps)"
        case .shutter:
            return Self.shutterLabel(auto ? live?.shutterSeconds ?? streamer.shutterSeconds
                                          : streamer.shutterSeconds)
        case .iso:
            return "\(Int((auto ? live?.iso ?? streamer.iso : streamer.iso).rounded()))"
        case .whiteBalance:
            let kelvin = auto ? live?.temperature ?? streamer.whiteBalanceTemperature
                              : streamer.whiteBalanceTemperature
            return "\(Int((kelvin / 10).rounded()) * 10)K"
        case .tint:
            let tint = auto ? live?.tint ?? 0 : streamer.whiteBalanceTint
            return String(format: "%+.0f", tint)
        case .exposure:
            return String(format: "%+.1f", streamer.exposureBias)
        case .focus:
            let position = auto ? live?.lensPosition ?? streamer.lensPosition
                                : streamer.lensPosition
            return String(format: "%.2f", position)
        }
    }

    private var lensFactor: Double {
        guard let index = streamer.availableLenses.firstIndex(of: streamer.selectedLens),
              index < streamer.lensFactors.count else { return 1 }
        return streamer.lensFactors[index]
    }

    static func factorLabel(_ factor: Double) -> String {
        if factor < 1 {
            return String(format: "%.1f", factor).replacingOccurrences(of: "0.", with: ".")
        }
        let whole = (factor - factor.rounded()).magnitude < 0.05
        return String(format: whole ? "%.0f" : "%.1f", factor)
    }

    static func shutterLabel(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "–" }
        guard seconds < 1 else { return String(format: "%.0fs", seconds) }
        return "1/\(Int((1 / seconds).rounded()))"
    }

    // MARK: - Dials

    @ViewBuilder private func dial(_ param: Param) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                if let target = lockTarget(param) {
                    chip(L("Auto"), on: !streamer.isLocked(target)) {
                        streamer.setLocked(target, !streamer.isLocked(target))
                    }
                }
                extras(param)
                Spacer(minLength: 0)
            }
            control(param)
        }
        .font(.footnote)
    }

    @ViewBuilder private func extras(_ param: Param) -> some View {
        switch param {
        case .lens:
            ForEach(sideLenses, id: \.id) { lens in
                chip(Self.factorLabel(factor(of: lens)), on: lens == streamer.selectedLens) {
                    if supports(lens) { streamer.selectedLens = lens }
                }
            }
            chip(L("Flip"), on: false) { streamer.flipCamera() }
        case .fps:
            ForEach(frameRates, id: \.self) { rate in
                chip("\(rate)", on: rate == streamer.fps) {
                    streamer.applyRemoteFormat(["fps": rate])
                }
            }
        case .whiteBalance:
            ForEach([3200, 4300, 5600], id: \.self) { kelvin in
                chip("\(kelvin)K", on: false) { lockWhiteBalance(temperature: Float(kelvin)) }
            }
            chip(L("Calibrate"), on: false) { streamer.calibrateWhiteBalance() }
        case .exposure:
            chip("0", on: streamer.exposureBias == 0) { streamer.exposureBias = 0 }
        default:
            EmptyView()
        }
    }

    @ViewBuilder private func control(_ param: Param) -> some View {
        switch param {
        case .lens:
            if streamer.camera.maxZoomFactor > 1 {
                Slider(value: zoomBinding, in: 1...streamer.camera.maxZoomFactor)
                    .accessibilityLabel(L("Zoom"))
            }
        case .fps:
            EmptyView()
        case .shutter:
            let stops = shutterStops
            Slider(value: Binding(
                get: { Double(Self.nearest(stops, streamer.shutterSeconds)) },
                set: { index in
                    touched()
                    streamer.shutterSeconds = stops[Int(index.rounded())]
                    streamer.exposureSetting.shutterManual = true
                }), in: 0...Double(max(stops.count - 1, 1)), step: 1)
                .accessibilityLabel(L("Shutter"))
                .accessibilityValue(Text(verbatim: Self.shutterLabel(streamer.shutterSeconds)))
        case .iso:
            let range = streamer.camera.isoRange
            Slider(value: Binding(
                get: { log2(Double(streamer.iso)) },
                set: { stop in
                    touched()
                    streamer.iso = min(max(Float(pow(2, stop)), range.lowerBound),
                                       range.upperBound)
                    streamer.exposureSetting.isoManual = true
                }), in: log2(Double(range.lowerBound))...log2(Double(max(range.upperBound, range.lowerBound + 1))))
                .accessibilityLabel(Text(verbatim: "ISO"))
                .accessibilityValue(Text(verbatim: value(.iso)))
        case .whiteBalance:
            Slider(value: Binding(
                get: { Double(streamer.whiteBalanceTemperature) },
                set: { lockWhiteBalance(temperature: Float($0)) }),
                   in: 2500...8000, step: 50)
                .accessibilityLabel(L("WB"))
                .accessibilityValue(Text(verbatim: value(.whiteBalance)))
        case .tint:
            Slider(value: Binding(
                get: { Double(streamer.whiteBalanceTint) },
                set: { tint in
                    lockWhiteBalance(temperature: streamer.whiteBalanceSetting == .locked
                        ? streamer.whiteBalanceTemperature
                        : live?.temperature ?? streamer.whiteBalanceTemperature)
                    streamer.whiteBalanceTint = Float(tint)
                }), in: -150...150, step: 1)
                .accessibilityLabel(L("Tint"))
                .accessibilityValue(Text(verbatim: value(.tint)))
        case .exposure:
            let range = streamer.camera.exposureBiasRange
            Slider(value: Binding(
                get: { Double(streamer.exposureBias) },
                set: { touched(); streamer.exposureBias = Float($0) }),
                   in: Double(range.lowerBound)...Double(range.upperBound), step: 1.0 / 3)
                .accessibilityLabel(Text(verbatim: "EV"))
                .accessibilityValue(Text(verbatim: value(.exposure)))
                .disabled(streamer.exposureSetting == .manual)
        case .focus:
            Slider(value: Binding(
                get: { Double(streamer.lensPosition) },
                set: { position in
                    touched()
                    streamer.lensPosition = Float(position)
                    streamer.focusSetting = .locked
                }), in: 0...1)
                .accessibilityLabel(L("Focus"))
                .accessibilityValue(Text(verbatim: value(.focus)))
        }
    }

    private func lockWhiteBalance(temperature: Float) {
        touched()
        if streamer.whiteBalanceSetting == .auto {
            streamer.whiteBalanceSetting = .locked
            streamer.whiteBalanceTint = live?.tint ?? 0
        }
        streamer.whiteBalanceTemperature = min(max(temperature, 2500), 8000)
    }

    private var zoomBinding: Binding<CGFloat> {
        Binding(get: { streamer.zoom }, set: { touched(); streamer.zoom = $0 })
    }

    private var sideLenses: [CameraManager.Lens] {
        streamer.availableLenses
            .filter { $0.position == streamer.selectedLens.position }
            .sorted { factor(of: $0) < factor(of: $1) }
    }

    private func factor(of lens: CameraManager.Lens) -> Double {
        guard let index = streamer.availableLenses.firstIndex(of: lens),
              index < streamer.lensFactors.count else { return 1 }
        return streamer.lensFactors[index]
    }

    private func supports(_ lens: CameraManager.Lens) -> Bool {
        CameraManager.supports(resolution: streamer.resolution,
                               fps: Int32(streamer.fps), lens: lens)
    }

    private var frameRates: [Int] {
        streamer.candidateFrameRates.filter {
            CameraManager.supports(resolution: streamer.resolution, fps: Int32($0),
                                   lens: streamer.selectedLens)
        }
    }

    private static let shutterDenominators: [Double] = [
        2, 3, 4, 5, 6, 8, 10, 13, 15, 20, 24, 25, 30, 40, 48, 50, 60, 80, 96, 100,
        120, 125, 160, 200, 250, 320, 400, 500, 640, 800, 1000, 1250, 1600,
        2000, 2500, 3200, 4000, 5000, 6400, 8000,
    ]

    private var shutterStops: [Double] {
        let lo = streamer.camera.minShutterSeconds * 0.999
        let hi = streamer.camera.maxShutterSeconds(fps: Int32(streamer.fps)) * 1.001
        let stops = Self.shutterDenominators.map { 1 / $0 }.filter { $0 >= lo && $0 <= hi }
        return stops.count > 1 ? stops : [hi, lo]
    }

    private static func nearest(_ values: [Double], _ value: Double) -> Int {
        values.indices.min { abs(values[$0] - value) < abs(values[$1] - value) } ?? 0
    }

    private func chip(_ title: String, on: Bool,
                      action: @escaping () -> Void) -> some View {
        Button {
            touched()
            action()
        } label: {
            Text(title)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, Theme.Space.m)
                .frame(minHeight: 32)
                .background(on ? Theme.accent : Theme.glassChip)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: - Scopes

    private var scopes: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Histogram")).font(Self.label).foregroundColor(Theme.textSecondary)
                Histogram(bins: scope.histogram)
                    .frame(height: 40)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Phone")).font(Self.label).foregroundColor(Theme.textSecondary)
                linkRow(L("Heat"), heat,
                        tint: thermal.rawValue >= ProcessInfo.ThermalState.serious.rawValue
                            ? Theme.connectAmber : Theme.textPrimary)
                linkRow(L("Connection"), streamer.obsTransport == "usb" ? "USB" : "Wi-Fi")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Mic")).font(Self.label).foregroundColor(Theme.textSecondary)
                if let level = scope.micLevel {
                    MicMeter(dbfs: level).frame(height: 8)
                    Text(String(format: "%.0f dBFS", level))
                        .font(.system(size: 10, design: .monospaced))
                } else {
                    Text(L("Off")).font(.system(size: 10))
                        .foregroundColor(Theme.textSecondary)
                }
            }
            .frame(width: 90, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private func linkRow(_ name: String, _ value: String,
                         tint: Color = Theme.textPrimary) -> some View {
        HStack(spacing: Theme.Space.xs) {
            Text(name)
                .font(.system(size: 10))
                .foregroundColor(Theme.textSecondary)
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(tint)
        }
        .lineLimit(1)
    }

    private var heat: String {
        switch thermal {
        case .fair: return L("Warm")
        case .serious, .critical: return L("Hot")
        default: return L("Cool")
        }
    }

    // MARK: - Tools

    private var toolRow: some View {
        HStack(spacing: 0) {
            tool(L("Flip"), "arrow.triangle.2.circlepath.camera", on: false,
                 tint: Theme.textPrimary) { streamer.flipCamera() }
            guidesMenu
            Button {
                streamer.stop()
            } label: {
                ZStack {
                    Circle().strokeBorder(Theme.textPrimary, lineWidth: 3)
                    RoundedRectangle(cornerRadius: 5).fill(Theme.errorRed)
                        .frame(width: 24, height: 24)
                }
                .frame(width: 60, height: 60)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(L("Stop camera"))
            tool(streamer.isPaused ? L("Resume") : L("Pause"),
                 streamer.isPaused ? "play.fill" : "pause.fill",
                 on: streamer.isPaused, tint: Theme.connectAmber) {
                streamer.setPaused(!streamer.isPaused, reason: .user)
            }
            .disabled(streamer.isPaused && streamer.pauseReason != .user)
            tool(L("Flashlight"), "flashlight.on.fill", on: streamer.flashlightOn,
                 tint: Theme.cameraYellow) { streamer.flashlightOn.toggle() }
                .disabled(!streamer.camera.hasFlashlight)
        }
    }

    private func tool(_ name: String, _ symbol: String, on: Bool, tint: Color,
                      action: @escaping () -> Void) -> some View {
        Button {
            touched()
            action()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 20))
                Text(name).font(.system(size: 9, weight: .semibold)).lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundColor(on ? tint : Theme.textSecondary)
            .frame(maxWidth: .infinity, minHeight: Theme.controlButton)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var guidesMenu: some View {
        SteadyMenu(key: [streamer.monitor.guide]) {
            Picker(L("Guides"), selection: guideBinding) {
                ForEach(Streamer.Guide.allCases) { guide in
                    Text(Self.guideName(guide)).tag(guide)
                }
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "grid").font(.system(size: 20))
                Text(L("Guides")).font(.system(size: 9, weight: .semibold)).lineLimit(1)
            }
            .foregroundColor(streamer.monitor.guide == .off ? Theme.textSecondary
                                                            : Theme.textPrimary)
            .frame(maxWidth: .infinity, minHeight: Theme.controlButton)
            .contentShape(Rectangle())
        }
        .equatable()
        .frame(maxWidth: .infinity)
        .accessibilityLabel(L("Guides"))
    }

    static func guideName(_ guide: Streamer.Guide) -> String {
        switch guide {
        case .off: return L("Off")
        case .grid: return L("Grid")
        default: return guide.rawValue
        }
    }

    private var guideBinding: Binding<Streamer.Guide> {
        Binding(get: { streamer.monitor.guide },
                set: { touched(); streamer.monitor.guide = $0 })
    }
}

/// A Menu that is rebuilt only when `key` changes. The views around it
/// redraw several times a second (live values, mic level, stats), and a
/// Menu rebuilt while open flashes and stops taking taps on its items.
struct SteadyMenu<Content: View, MenuLabel: View>: View, Equatable {
    let key: [AnyHashable]
    @ViewBuilder let content: () -> Content
    @ViewBuilder let label: () -> MenuLabel

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.key == rhs.key }

    var body: some View {
        Menu(content: content, label: label)
    }
}

/// Luma histogram, 64 bins, shadows on the left.
private struct Histogram: View {
    let bins: [Float]

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .color(.white.opacity(0.06)))
            guard bins.count > 1 else { return }
            var path = Path()
            path.move(to: CGPoint(x: 0, y: size.height))
            for (index, bin) in bins.enumerated() {
                let x = size.width * CGFloat(index) / CGFloat(bins.count - 1)
                path.addLine(to: CGPoint(x: x, y: size.height * (1 - CGFloat(bin))))
            }
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
            context.fill(path, with: .color(.white.opacity(0.7)))
        }
        .accessibilityHidden(true)
    }
}

/// Peak meter from -48 to 0 dBFS: green, yellow from -12, red from -3.
private struct MicMeter: View {
    let dbfs: Float

    var body: some View {
        GeometryReader { proxy in
            let fill = CGFloat(min(max((dbfs + 48) / 48, 0), 1))
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.white.opacity(0.12))
                Rectangle()
                    .fill(dbfs > -3 ? Theme.errorRed
                          : dbfs > -12 ? Theme.cameraYellow : Theme.liveGreen)
                    .frame(width: proxy.size.width * fill)
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))
        }
        .accessibilityHidden(true)
    }
}

/// The frame guides over the preview. Drawn in both interfaces: they
/// can be switched on from OBS or the web panel whichever one the phone
/// shows.
struct MonitorOverlay: View {
    @EnvironmentObject private var streamer: Streamer

    var body: some View {
        GeometryReader { proxy in
            guides(in: Self.pictureRect(in: proxy.size))
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Where the 16:9 picture lands in the preview (aspect fit).
    static func pictureRect(in size: CGSize) -> CGRect {
        let aspect: CGFloat = size.width < size.height ? 9.0 / 16 : 16.0 / 9
        var rect = CGRect(origin: .zero, size: size)
        if size.width / max(size.height, 1) > aspect {
            rect.size.width = size.height * aspect
        } else {
            rect.size.height = size.width / aspect
        }
        rect.origin = CGPoint(x: (size.width - rect.width) / 2,
                              y: (size.height - rect.height) / 2)
        return rect
    }

    @ViewBuilder private func guides(in rect: CGRect) -> some View {
        let guide = streamer.monitor.guide
        if guide == .grid {
            Path { path in
                for third in [CGFloat(1) / 3, CGFloat(2) / 3] {
                    path.move(to: CGPoint(x: rect.minX + rect.width * third, y: rect.minY))
                    path.addLine(to: CGPoint(x: rect.minX + rect.width * third, y: rect.maxY))
                    path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * third))
                    path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * third))
                }
            }
            .stroke(Color.white.opacity(0.35), lineWidth: 1)
        } else if let aspect = guide.aspect {
            let inner = Self.frameLines(aspect: aspect, in: rect)
            Path { path in
                path.addRect(rect)
                path.addRect(inner)
            }
            .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
            Path { $0.addRect(inner) }
                .stroke(Color.white.opacity(0.6), lineWidth: 1)
        }
    }

    /// The guide's frame inside the picture. The aspect is the stream's
    /// (landscape); a portrait preview shows that picture turned, so the
    /// crop runs along the other axis.
    static func frameLines(aspect: CGFloat, in rect: CGRect) -> CGRect {
        let portrait = rect.width < rect.height
        let streamWidth = portrait ? rect.height : rect.width
        let streamHeight = portrait ? rect.width : rect.height
        var width = streamWidth
        var height = streamHeight
        if aspect > streamWidth / streamHeight {
            height = streamWidth / aspect
        } else {
            width = streamHeight * aspect
        }
        let size = portrait ? CGSize(width: height, height: width)
                            : CGSize(width: width, height: height)
        return CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                      width: size.width, height: size.height)
    }
}
