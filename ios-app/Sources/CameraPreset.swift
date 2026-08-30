import Foundation
import SwiftUI

/// A saved set of camera looks — the manual exposure, white balance, zoom
/// and focus values that someone shooting in the same room under the same
/// lights re-dials every single session (#107).
///
/// Every group is optional and `nil` means *not included*: a preset that
/// carries only white balance leaves your exposure exactly where it is
/// wherever it applies. That is the "choose which settings are included"
/// half of the feature, and it is why these are optionals rather than a
/// flat struct with `include` flags — a value that isn't included can't be
/// stored, so it can't be applied by mistake.
struct CameraPreset: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String

    /// AE bias, or the full manual triple. Stored together because
    /// applying an ISO without saying whether the camera is in manual
    /// exposure is meaningless.
    struct Exposure: Codable, Equatable {
        var manual: Bool
        var bias: Float
        var iso: Float
        var shutterSeconds: Double
    }
    struct WhiteBalance: Codable, Equatable {
        var locked: Bool
        var temperature: Float
    }
    struct Focus: Codable, Equatable {
        var locked: Bool
        var lensPosition: Float
    }

    var exposure: Exposure? = nil
    var whiteBalance: WhiteBalance? = nil
    var zoom: Double? = nil
    var focus: Focus? = nil

    /// `CameraManager.Lens.id` this preset belongs to, applied whenever
    /// that camera comes up. nil = applies to no camera on its own (still
    /// usable as the default, or by hand).
    var lensID: String? = nil

    /// A preset holding nothing would apply nothing — refuse to save one
    /// rather than leave a row that does nothing when tapped.
    var isEmpty: Bool {
        exposure == nil && whiteBalance == nil && zoom == nil && focus == nil
    }

    /// One line naming what this preset carries, for the list row.
    var summary: String {
        var parts: [String] = []
        if let exposure {
            parts.append(exposure.manual ? "Manual exposure" : "Auto exposure")
        }
        if whiteBalance != nil { parts.append("White balance") }
        if zoom != nil { parts.append("Zoom") }
        if focus != nil { parts.append("Focus") }
        return parts.isEmpty ? "Nothing saved" : parts.joined(separator: " · ")
    }
}

/// Stores the presets, which one is the default, and whether presets are
/// allowed to apply themselves at all.
///
/// Same shape as `TallySettings`: a JSON blob in `UserDefaults`, not
/// @MainActor so view property initializers can reach it.
final class PresetManager: ObservableObject {
    static let shared = PresetManager()

    private static let presetsKey = "cameraPresets"
    private static let defaultKey = "defaultPresetID"
    private static let autoApplyKey = "presetsAutoApply"

    @Published var presets: [CameraPreset] {
        didSet { save() }
    }

    /// The preset applied at stream start for a camera that has none of
    /// its own. Held here rather than as an `isDefault` flag on each
    /// preset so "two defaults" is unrepresentable.
    @Published var defaultPresetID: UUID? {
        didSet {
            UserDefaults.standard.set(defaultPresetID?.uuidString,
                                      forKey: Self.defaultKey)
        }
    }

    /// The master switch (Options → Presets). Off means nothing applies
    /// itself; presets can still be applied by hand from the list.
    @Published var autoApplyEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoApplyEnabled,
                                      forKey: Self.autoApplyKey)
        }
    }

    private init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.presetsKey),
           let saved = try? JSONDecoder().decode([CameraPreset].self,
                                                 from: data) {
            presets = saved
        } else {
            presets = []
        }
        defaultPresetID = defaults.string(forKey: Self.defaultKey)
            .flatMap(UUID.init(uuidString:))
        autoApplyEnabled = defaults.object(forKey: Self.autoApplyKey)
            as? Bool ?? true
    }

    private func save() {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: Self.presetsKey)
        }
        // A deleted preset must not stay the default: the id would dangle
        // and stream start would silently apply nothing.
        if let id = defaultPresetID, !presets.contains(where: { $0.id == id }) {
            defaultPresetID = nil
        }
    }

    var defaultPreset: CameraPreset? {
        presets.first { $0.id == defaultPresetID }
    }

    /// What should apply when this camera comes up: the camera's own
    /// preset, or the default when it has none.
    func preset(forLens lensID: String) -> CameraPreset? {
        presets.first { $0.lensID == lensID } ?? defaultPreset
    }

    /// Assigning a camera takes it off whichever preset had it — one
    /// camera can't auto-apply two presets, and the last edit wins.
    func upsert(_ preset: CameraPreset) {
        if let lens = preset.lensID {
            for index in presets.indices
            where presets[index].lensID == lens && presets[index].id != preset.id {
                presets[index].lensID = nil
            }
        }
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[index] = preset
        } else {
            presets.append(preset)
        }
    }
}
