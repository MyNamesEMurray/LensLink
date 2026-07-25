import SwiftUI

/// Which app conditions the tally border can announce. The raw values are
/// the persistence format — renaming one silently resets that row to its
/// default, so don't.
enum TallyStatus: String, Codable, CaseIterable {
    case onAir
    case preview
    case connectionLost
    case calibrating
    case syncLocked

    var displayName: String {
        switch self {
        case .onAir: return "On air"
        case .preview: return "In preview"
        case .connectionLost: return "Connection lost"
        case .calibrating: return "Calibrating lip-sync"
        case .syncLocked: return "Lip-sync locked"
        }
    }

    var explanation: String {
        switch self {
        case .onAir: return "The camera is in OBS's live output."
        case .preview: return "Visible in OBS (preview or a projector) but not live."
        case .connectionLost: return "Streaming, but the link to OBS dropped."
        case .calibrating: return "Auto lip-sync is measuring or re-measuring."
        case .syncLocked: return "Auto lip-sync has locked on."
        }
    }
}

/// The border colours a status can be given. "None" means the status
/// doesn't light the border at all — priority then falls through to the
/// next status in the list.
enum TallyColor: String, Codable, CaseIterable {
    case none
    case red
    case amber
    case green
    case blue
    case purple
    case white

    var displayName: String { rawValue == "none" ? "Off" : rawValue.capitalized }

    /// Border colour; nil for `.none`. Values come from the shared status
    /// palette (docs/UI_DESIGN.md) so the border speaks the same colour
    /// language as everything else.
    var color: Color? {
        switch self {
        case .none: return nil
        case .red: return Theme.tallyLive
        case .amber: return Theme.connectAmber
        case .green: return Theme.liveGreen
        case .blue: return Theme.accent
        case .purple: return Theme.tallyPurple
        case .white: return .white
        }
    }
}

/// One row of the tally configuration: a status and the colour it shows.
/// Array order IS the priority order — first matching row with a colour
/// wins.
struct TallyEntry: Codable, Equatable, Identifiable {
    var status: TallyStatus
    var color: TallyColor
    var id: String { status.rawValue }
}

/// Persistent tally-light configuration. The defaults reproduce the
/// original fixed behaviour exactly (red on air, amber preview, nothing
/// else), so nobody sees a change until they opt into one.
/// Not @MainActor: it's referenced from view property initializers, which
/// aren't isolated, and everything it touches (UserDefaults) is
/// thread-safe; in practice only the UI writes it.
final class TallySettings: ObservableObject {
    static let shared = TallySettings()
    private static let key = "tallyConfig"

    static let defaults: [TallyEntry] = [
        TallyEntry(status: .onAir, color: .red),
        TallyEntry(status: .preview, color: .amber),
        TallyEntry(status: .connectionLost, color: .none),
        TallyEntry(status: .calibrating, color: .none),
        TallyEntry(status: .syncLocked, color: .none),
    ]

    @Published var entries: [TallyEntry] {
        didSet {
            if let data = try? JSONEncoder().encode(entries) {
                UserDefaults.standard.set(data, forKey: Self.key)
            }
        }
    }

    private init() {
        var loaded = Self.defaults
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([TallyEntry].self,
                                                 from: data) {
            // Merge, don't replace: statuses added in a later version keep
            // their default colour and slot in at their default position
            // relative to what survived.
            loaded = saved.filter { entry in
                Self.defaults.contains { $0.status == entry.status }
            }
            for def in Self.defaults where !loaded.contains(where: {
                $0.status == def.status
            }) {
                loaded.append(def)
            }
        }
        entries = loaded
    }

    /// The border colour for the current conditions: the first (highest
    /// priority) entry whose status is active and isn't "Off". Also
    /// reports the winning status, for width decisions.
    func activeLight(for active: Set<TallyStatus>)
        -> (status: TallyStatus, color: Color)? {
        for entry in entries where active.contains(entry.status) {
            if let color = entry.color.color {
                return (entry.status, color)
            }
        }
        return nil
    }
}

/// Options → Tally light: colour per status, drag to set priority.
struct TallyLightOptionsView: View {
    @ObservedObject private var settings = TallySettings.shared

    var body: some View {
        List {
            Section {
                ForEach($settings.entries) { $entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.status.displayName)
                            Text(entry.status.explanation)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Picker("", selection: $entry.color) {
                            ForEach(TallyColor.allCases, id: \.self) { c in
                                Label {
                                    Text(c.displayName)
                                } icon: {
                                    Image(systemName: c == .none
                                          ? "circle.slash" : "circle.fill")
                                }
                                .tint(c.color)
                                .tag(c)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                .onMove { from, to in
                    settings.entries.move(fromOffsets: from, toOffset: to)
                }
            } header: {
                Text("Statuses, highest priority first")
            } footer: {
                Text("The border around the Live screen shows the colour of the highest status in this list that's currently true. Set a status to Off and it's skipped — lower statuses show through. Tap Edit to reorder.")
            }

            Section {
                Button("Reset to defaults") {
                    settings.entries = TallySettings.defaults
                }
                .disabled(settings.entries == TallySettings.defaults)
            }
        }
        .navigationTitle("Tally light")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
    }
}
