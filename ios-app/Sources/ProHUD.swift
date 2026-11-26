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
    /// Portrait: the picture sits in an inset frame under the status bar
    /// and the bottom rows sit on plain black below it.
    var frame: EdgeInsets?

    enum Param: CaseIterable {
        case lens, fps, shutter, iso, whiteBalance, tint, exposure, focus
    }

    @State private var open: Param?
    /// What auto is doing right now, polled while this view is up.
    @State private var live: CameraManager.LiveValues?

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
            .padding(.horizontal, frame?.leading ?? 0)
            Spacer()
            VStack(spacing: Theme.Space.s) {
                meters
                toolRow
            }
            .padding(Theme.Space.s)
            .padding(.horizontal, frame?.leading ?? 0)
            .background(Color.black.opacity(frame == nil ? 0.6 : 0).ignoresSafeArea(edges: .bottom))
        }
        .foregroundColor(Theme.textPrimary)
        .task {
            while !Task.isCancelled {
                live = streamer.camera.liveValues
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    // MARK: - Top bar

    /// Weights of the top bar's boxes: status, link, frames, format.
    /// Fixed shares, so a longer status word never moves the others.
    private static let topWeights: [CGFloat] = [1.3, 1.5, 1.1, 1.3]
    private static let boxHeight: CGFloat = 40
    private static let moreWidth: CGFloat = 36
    private static let gap: CGFloat = 3

    private var topBar: some View {
        GeometryReader { proxy in
            let spare = proxy.size.width - Self.moreWidth
                - Self.gap * CGFloat(Self.topWeights.count)
            let unit = max(spare, 0) / Self.topWeights.reduce(0, +)
            HStack(spacing: Self.gap) {
                statusBox.frame(width: unit * Self.topWeights[0])
                linkBox.frame(width: unit * Self.topWeights[1])
                framesBox.frame(width: unit * Self.topWeights[2])
                Text(formatLabel)
                    .font(Self.mono)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .proBox()
                    .frame(width: unit * Self.topWeights[3])
                moreMenu
            }
        }
        .frame(height: Self.boxHeight)
    }

    private var statusBox: some View {
        HStack(spacing: Theme.Space.xs) {
            Circle().fill(streamer.status.tint).frame(width: 7, height: 7)
            Text(streamer.status.displayName)
                .font(Self.mono)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .proBox()
        .accessibilityElement(children: .combine)
    }

    /// The connection, once, over what it is carrying.
    private var linkBox: some View {
        VStack(spacing: 1) {
            Text(verbatim: streamer.obsTransport == "usb" ? "USB" : "Wi-Fi")
                .font(Self.label)
                .foregroundColor(Theme.textSecondary)
            Text(verbatim: streamer.health.map { String(format: "%.1f Mb/s", $0.megabitsPerSecond) } ?? "–")
                .font(Self.mono)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .proBox()
        .accessibilityElement(children: .combine)
    }

    /// Frame rate over dropped frames: numbers left, units in a fixed
    /// column beside them, the pair centred in the box.
    private var framesBox: some View {
        let health = streamer.health
        return VStack(spacing: 1) {
            unitRow(health.map { "\($0.fps)" } ?? "–", "fps")
            unitRow(health.map { String($0.droppedFrames) } ?? "–", L("drop"))
        }
        .proBox()
        .accessibilityElement(children: .combine)
    }

    private func unitRow(_ value: String, _ unit: String) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(Self.mono)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(unit)
                .font(Self.label)
                .foregroundColor(Theme.textSecondary)
                .lineLimit(1)
                .fixedSize()
                .frame(width: 26, alignment: .leading)
        }
        .frame(maxWidth: 64, alignment: .leading)
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
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .frame(width: Self.moreWidth, height: Self.boxHeight)
                .background(Self.boxFill)
                .clipShape(RoundedRectangle(cornerRadius: Self.boxRadius, style: .continuous))
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

    /// Equal boxes, one per value: a long value shrinks inside its box
    /// rather than pushing its neighbours.
    private var strip: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Self.gap),
                                 count: params.count), spacing: Self.gap) {
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
            VStack(spacing: 2) {
                Text(title(param))
                    .font(Self.label)
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(value(param))
                    .font(Self.mono)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .proBox(selected: selected)
            .frame(height: Theme.controlButton)
            .overlay(alignment: .topTrailing) { badge(param) }
            .overlay(alignment: .bottom) {
                if selected {
                    Rectangle().fill(Theme.accent).frame(height: 2)
                        .padding(.horizontal, 4)
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
            Circle()
                .fill(Theme.accent)
                .frame(width: 6, height: 6)
                .padding(3)
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

    // MARK: - Battery and mic

    private var meters: some View {
        HStack(spacing: Theme.Space.l) {
            if let percent = battery.percent {
                HStack(spacing: Theme.Space.xs) {
                    Image(systemName: StreamingView.batterySymbol(percent))
                    if battery.isCharging {
                        Image(systemName: "bolt.fill").font(.caption2)
                    }
                    Text(L("%lld%%", percent)).font(Self.mono)
                }
                .foregroundColor(batteryTint(percent))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(battery.isCharging
                    ? L("Battery %lld percent, charging", percent)
                    : L("Battery %lld percent", percent))
            }
            HStack(spacing: Theme.Space.s) {
                Text(L("Mic")).font(Self.label).foregroundColor(Theme.textSecondary)
                if let level = scope.micLevel {
                    MicMeter(dbfs: level).frame(height: 8)
                    Text(String(format: "%.0f dBFS", level))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .lineLimit(1)
                        .fixedSize()
                } else {
                    Text(L("Off")).font(Self.label).foregroundColor(Theme.textSecondary)
                    Spacer(minLength: 0)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// The idle screen's rule: red at 20% or below, amber in Low Power
    /// Mode, plain while charging or fine.
    private func batteryTint(_ percent: Int) -> Color {
        guard !battery.isCharging else { return Theme.textPrimary }
        if percent <= 20 { return Theme.errorRed }
        return battery.lowPowerMode ? Theme.connectAmber : Theme.textPrimary
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
                                                            : Theme.accent)
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

extension ProHUD {
    /// Dark see-through boxes: they float on the picture with no panel.
    static let boxFill = Color.black.opacity(0.5)
    static let boxSelected = Color.black.opacity(0.75)
    static let boxRadius: CGFloat = 6
    /// The picture frame's margin from the screen edges, in portrait.
    static let frameInset: CGFloat = 12
    static let frameRadius: CGFloat = 12
    /// Height kept below the frame for the meter and tool rows.
    static let bottomReserve: CGFloat = 110

    /// The insets that put the 9:16 picture in a rounded frame under the
    /// status bar, leaving bottomReserve for the controls. Nil in
    /// landscape, where the picture keeps the whole screen.
    static func frameInsets(screen: CGSize, safe: EdgeInsets) -> EdgeInsets? {
        guard screen.width < screen.height else { return nil }
        let room = screen.height - safe.top - safe.bottom - bottomReserve
        let height = max(min((screen.width - 2 * frameInset) * 16 / 9, room), 0)
        let side = (screen.width - height * 9 / 16) / 2
        return EdgeInsets(top: safe.top, leading: side,
                          bottom: screen.height - safe.top - height, trailing: side)
    }
}

private extension View {
    /// One of the Pro interface's boxes: it fills the frame it is given
    /// and centres what it holds.
    func proBox(selected: Bool = false) -> some View {
        padding(.horizontal, 3)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(selected ? ProHUD.boxSelected : ProHUD.boxFill)
            .clipShape(RoundedRectangle(cornerRadius: ProHUD.boxRadius,
                                        style: .continuous))
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
    /// The picture frame's insets from the screen edges, when framed.
    var insets = EdgeInsets()

    var body: some View {
        GeometryReader { proxy in
            guides(in: Self.pictureRect(in: proxy.size))
        }
        .padding(insets)
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
