import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// The widget extension: today it holds exactly one thing, the stream's
/// Live Activity. A stream is a live, timed, stoppable thing — what Live
/// Activities exist for — so the Lock Screen card says where the picture
/// is going, how long it has been going, and whether it is on air, with
/// Pause and Stop that work without unlocking (iOS 17; on 16 the card is
/// read-only). The Dynamic Island carries the compact form: a dot in the
/// status colour and the elapsed time.
@main
struct LensLinkWidgets: WidgetBundle {
    var body: some Widget {
        StreamActivityWidget()
    }
}

/// The three status colours, the same hex as the app's `Theme` and the
/// web panel (docs/UI_DESIGN.md §2) — inlined rather than importing the
/// app's DesignSystem, which drags UIKit-side helpers this target has no
/// use for.
private enum Palette {
    static let live = Color(red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255)
    static let amber = Color(red: 0xFF / 255, green: 0x9F / 255, blue: 0x0A / 255)
    static let onAir = Color(red: 0xFF / 255, green: 0x3B / 255, blue: 0x30 / 255)
    static let errorRed = Color(red: 0xFF / 255, green: 0x45 / 255, blue: 0x3A / 255)
}

struct StreamActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StreamActivityAttributes.self) { context in
            LockScreenCard(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        StatusDot(state: context.state, size: 10)
                        Text(statusLine(context.state))
                            .font(.headline)
                            .lineLimit(1)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ElapsedTimer(since: context.state.startedAt)
                        .font(.headline.monospacedDigit())
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(destinationLine(context.state))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ActivityButtons(paused: context.state.paused)
                }
            } compactLeading: {
                StatusDot(state: context.state, size: 8)
                    .padding(.leading, 4)
            } compactTrailing: {
                ElapsedTimer(since: context.state.startedAt)
                    .font(.caption.monospacedDigit())
                    .frame(maxWidth: 48)
                    .padding(.trailing, 4)
            } minimal: {
                StatusDot(state: context.state, size: 8)
            }
            .keylineTint(tint(context.state))
        }
    }
}

/// "On air", "Paused", "Live", or whatever the status word is: the tally
/// outranks the plain status because it is the thing the card exists
/// to show.
private func statusLine(_ state: StreamActivityAttributes.ContentState) -> String {
    if state.paused { return "Paused" }
    if state.onAir { return "On air" }
    return state.statusWord
}

/// "Studio-Mac · 4K · 60 fps · HEVC · USB".
private func destinationLine(_ state: StreamActivityAttributes.ContentState) -> String {
    var parts = [state.host, state.format]
    if !state.transport.isEmpty { parts.append(state.transport) }
    return parts.joined(separator: " · ")
}

/// Red on air, amber held, green live, red for an error message: the
/// same reading these colours carry everywhere else in the product.
private func tint(_ state: StreamActivityAttributes.ContentState) -> Color {
    if state.paused { return Palette.amber }
    if state.onAir { return Palette.onAir }
    switch state.statusWord {
    case "Live": return Palette.live
    case "Waiting for OBS…", "OBS connected — ready": return Palette.amber
    default: return Palette.errorRed
    }
}

private struct StatusDot: View {
    let state: StreamActivityAttributes.ContentState
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(tint(state))
            .frame(width: size, height: size)
    }
}

/// Counts up from the stream's start on its own: the system renders a
/// `.timer` text without a single update from the app.
private struct ElapsedTimer: View {
    let since: Date

    var body: some View {
        Text(since, style: .timer)
            .monospacedDigit()
    }
}

/// Pause/Resume and Stop, on iOS 17 where a Live Activity can carry
/// buttons at all. Absent on 16, where the card is a readout.
private struct ActivityButtons: View {
    let paused: Bool

    var body: some View {
        if #available(iOS 17.0, *) {
            HStack(spacing: 8) {
                Button(intent: PauseStreamActivityIntent()) {
                    Label(paused ? "Resume" : "Pause",
                          systemImage: paused ? "play.fill" : "pause.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .tint(.white.opacity(0.2))
                Button(intent: StopStreamActivityIntent()) {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .tint(Palette.errorRed)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
        }
    }
}

/// The Lock Screen card: icon, name and destination on the left, the
/// tally word and elapsed time on the right, the two buttons beneath.
private struct LockScreenCard: View {
    let state: StreamActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "video.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(tint(state))
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 11,
                                                     style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("LensLink")
                        .font(.headline)
                    Text(destinationLine(state))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 6) {
                        StatusDot(state: state, size: 8)
                        Text(statusLine(state))
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(tint(state))
                    }
                    ElapsedTimer(since: state.startedAt)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: 64, alignment: .trailing)
                }
            }
            ActivityButtons(paused: state.paused)
        }
        .padding(14)
        .foregroundColor(.white)
    }
}
