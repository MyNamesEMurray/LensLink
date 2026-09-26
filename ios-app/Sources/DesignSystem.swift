import SwiftUI

/// Shared visual tokens for the app, implementing docs/UI_DESIGN.md.
/// Keep these values in sync with that document and the web panel CSS.
enum Theme {
    // Accent
    static let accent = Color(hex: 0x3D7BFF)
    static let accentPressed = Color(hex: 0x2E63E6)

    // Status palette (mirrors iOS system semantic colours)
    static let idleGrey = Color(hex: 0x8E8E93)
    static let connectAmber = Color(hex: 0xFF9F0A)
    static let liveGreen = Color(hex: 0x30D158)
    static let errorRed = Color(hex: 0xFF453A)

    /// Tally. Deliberately its own token rather than `errorRed`: on air is
    /// not an error, and the two must stay independently adjustable even
    /// though both are red today. Preview borrows `connectAmber` — same
    /// "linked, not yet live" meaning it already carries. Purple exists
    /// only as a user-assignable tally colour (mirrors iOS systemPurple).
    static let tallyLive = Color(hex: 0xFF3B30)
    static let tallyPreview = connectAmber
    static let tallyPurple = Color(hex: 0xBF5AF2)

    // Over-video surfaces
    static let glassPanel = Color.black.opacity(0.55)
    static let glassChip = Color.white.opacity(0.12)
    static func glassChipOn() -> Color { accent.opacity(0.9) }

    /// The Camera app's own yellow for the selected lens button and the
    /// dial's needle and readout: the one place the Live screen borrows a
    /// system convention instead of the accent, because that is the
    /// colour every iPhone owner already reads as "the camera setting
    /// I'm touching".
    static let cameraYellow = Color(hex: 0xFFD60A)

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.6)

    static let glassPanelSolid = Color.black.opacity(0.9)
    static let glassChipSolid = Color(white: 0.22)
    static let textSecondaryIncreased = Color.white.opacity(0.9)
    static let hairlineStrong = Color.white.opacity(0.5)

    // Spacing scale
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
    }

    // Radius
    enum Radius {
        static let panel: CGFloat = 16
        static let chip: CGFloat = 12
    }

    static let controlButton: CGFloat = 44
    static let iconSize: CGFloat = 22
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1)
    }
}

extension UIColor {
    /// Same palette as Color(hex:), for the places SwiftUI colour
    /// modifiers don't reach (rendered UIImages in menus).
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

/// A circular 44 pt glass control button (icon only). `isOn` fills it
/// with the accent colour (e.g. flashlight on).
struct ControlButton: View {
    let label: String
    let systemImage: String
    var isOn: Bool?
    var highlighted: Bool
    var destructive: Bool
    var inputLabels: [String]
    let action: () -> Void

    init(_ label: String, systemImage: String, isOn: Bool? = nil,
         highlighted: Bool = false, destructive: Bool = false,
         inputLabels: [String] = [], action: @escaping () -> Void) {
        self.label = label
        self.systemImage = systemImage
        self.isOn = isOn
        self.highlighted = highlighted
        self.destructive = destructive
        self.inputLabels = inputLabels
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(Theme.textPrimary)
                .frame(width: Theme.controlButton, height: Theme.controlButton)
                .glassBackground(Circle(), style: style)
        }
        .accessibilityLabel(label)
        .accessibilityValue(stateValue)
        .accessibilityInputLabels([label] + inputLabels)
        .accessibilityShowsLargeContentViewer {
            Label(label, systemImage: systemImage)
        }
    }

    private var style: GlassStyle {
        if destructive { return .solid(Theme.errorRed.opacity(0.9)) }
        return (isOn ?? highlighted) ? .chipOn : .chip
    }

    private var stateValue: String {
        guard let isOn else { return "" }
        return isOn ? L("On") : L("Off")
    }
}

enum GlassStyle {
    case panel
    case chip
    case chipOn
    case scrim(Double)
    case solid(Color)
}

private struct GlassBackground<S: InsettableShape>: ViewModifier {
    let shape: S
    let style: GlassStyle
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background(fill, in: shape)
            .overlay(shape.strokeBorder(Theme.hairlineStrong, lineWidth: 1)
                        .opacity(contrast == .increased ? 1 : 0))
    }

    private var opaque: Bool { reduceTransparency || contrast == .increased }

    private var fill: Color {
        switch style {
        case .panel: return opaque ? Theme.glassPanelSolid : Theme.glassPanel
        case .chip: return opaque ? Theme.glassChipSolid : Theme.glassChip
        case .chipOn: return opaque ? Theme.accent : Theme.glassChipOn()
        case .scrim(let opacity):
            return opaque ? Theme.glassPanelSolid : Color.black.opacity(opacity)
        case .solid(let colour): return colour
        }
    }
}

private struct OnGlassText: ViewModifier {
    let normal: Color
    let increased: Color
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.foregroundColor(contrast == .increased ? increased : normal)
    }
}

extension View {
    func glassBackground<S: InsettableShape>(_ shape: S,
                                             style: GlassStyle) -> some View {
        modifier(GlassBackground(shape: shape, style: style))
    }

    func onGlassText(_ normal: Color,
                     increased: Color = Theme.textPrimary) -> some View {
        modifier(OnGlassText(normal: normal, increased: increased))
    }

    func secondaryOnGlass() -> some View {
        onGlassText(Theme.textSecondary, increased: Theme.textSecondaryIncreased)
    }

    /// Floating control panel: padding + translucent material + radius.
    func glassPanel() -> some View {
        self
            .padding(Theme.Space.l)
            .glassBackground(RoundedRectangle(cornerRadius: Theme.Radius.panel),
                             style: .panel)
    }

    /// Small pill used for the status chip.
    func glassPill() -> some View {
        self
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, Theme.Space.s)
            .glassBackground(Capsule(), style: .panel)
    }
}
