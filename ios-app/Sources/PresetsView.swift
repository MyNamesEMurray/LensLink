import SwiftUI

/// Options → Presets: the saved camera looks, which camera each one comes
/// up on, and the master switch for applying them automatically (#107).
struct PresetsView: View {
    @EnvironmentObject private var streamer: Streamer
    @ObservedObject private var manager = PresetManager.shared

    @State private var editing: CameraPreset?

    var body: some View {
        List {
            Section {
                Toggle("Apply presets automatically",
                       isOn: $manager.autoApplyEnabled)
            } footer: {
                Text("A preset applies when its camera starts, and the default applies to any camera without one. Changing a setting by hand pauses this until you resume it from the Live screen.")
            }

            Section {
                if manager.presets.isEmpty {
                    Text("No presets yet")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(manager.presets) { preset in
                        Button {
                            editing = preset
                        } label: {
                            row(preset)
                        }
                        .foregroundColor(.primary)
                    }
                    .onDelete { offsets in
                        manager.presets.remove(atOffsets: offsets)
                    }
                }

                Button("New preset") {
                    editing = CameraPreset(name: "", lensID: streamer.selectedLens.id)
                }
            } header: {
                Text("Presets")
            }

            if !manager.presets.isEmpty {
                Section {
                    // Applying by hand works whatever the master switch
                    // says — it is an explicit act, not an automatic one.
                    ForEach(manager.presets) { preset in
                        Button("Apply \(preset.name)") {
                            streamer.apply(preset)
                        }
                    }
                } header: {
                    Text("Apply now")
                } footer: {
                    Text("Applies to the running camera immediately.")
                }
            }
        }
        .navigationTitle("Presets")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { preset in
            PresetEditorView(preset: preset)
                .environmentObject(streamer)
        }
    }

    private func row(_ preset: CameraPreset) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(preset.name)
                if preset.id == manager.defaultPresetID {
                    Text("Default")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.accent.opacity(0.2), in: Capsule())
                }
            }
            Text(subtitle(preset))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func subtitle(_ preset: CameraPreset) -> String {
        guard let lensID = preset.lensID,
              let lens = streamer.availableLenses.first(where: {
                  $0.id == lensID
              }) else {
            return preset.summary
        }
        return "\(lens.label) · \(preset.summary)"
    }
}

/// Create or edit one preset: its name, which groups of settings it
/// carries, the values themselves, and the camera it comes up on.
///
/// The values are editable here rather than only captured from the live
/// camera, because Options is reachable only from the Setup screen — you
/// cannot be looking at the Live screen's sliders and this form at the
/// same time. **Fill from current settings** covers the other direction:
/// dial the look in on the Live screen, stop, and copy it in (stopping a
/// stream doesn't reset the camera values).
struct PresetEditorView: View {
    @EnvironmentObject private var streamer: Streamer
    @ObservedObject private var manager = PresetManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var draft: CameraPreset
    @State private var isDefault: Bool

    init(preset: CameraPreset) {
        _draft = State(initialValue: preset)
        _isDefault = State(
            initialValue: preset.id == PresetManager.shared.defaultPresetID)
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                    Button("Fill from current settings") { fillFromCurrent() }
                }

                Section {
                    Toggle("Exposure", isOn: exposureIncluded)
                    if let exposure = draft.exposure {
                        Picker("Mode", selection: exposureMode) {
                            Text("Auto").tag(false)
                            Text("Manual").tag(true)
                        }
                        .pickerStyle(.segmented)
                        if exposure.manual {
                            slider("ISO", value: isoBinding,
                                   range: isoRange,
                                   readout: "\(Int(draft.exposure?.iso ?? 0))")
                            slider("Shutter", value: shutterBinding,
                                   range: 0...1,
                                   readout: shutterReadout)
                        } else {
                            slider("Bias", value: biasBinding,
                                   range: biasRange,
                                   readout: String(format: "%+.1f",
                                                   exposure.bias))
                        }
                    }
                } header: {
                    Text("Included settings")
                }

                Section {
                    Toggle("White balance", isOn: whiteBalanceIncluded)
                    if let wb = draft.whiteBalance {
                        Picker("Mode", selection: whiteBalanceMode) {
                            Text("Auto").tag(false)
                            Text("Locked").tag(true)
                        }
                        .pickerStyle(.segmented)
                        if wb.locked {
                            slider("Temperature", value: temperatureBinding,
                                   range: 2500...8000,
                                   readout: "\(Int(wb.temperature))K")
                        }
                    }
                }

                Section {
                    Toggle("Zoom", isOn: zoomIncluded)
                    if draft.zoom != nil {
                        slider("Zoom", value: zoomBinding,
                               range: 1...max(streamer.camera.maxZoomFactor,
                                              1.1),
                               readout: String(format: "%.1f×",
                                               draft.zoom ?? 1))
                    }
                }

                Section {
                    Toggle("Focus", isOn: focusIncluded)
                    if let focus = draft.focus {
                        Picker("Mode", selection: focusMode) {
                            Text("Auto").tag(false)
                            Text("Locked").tag(true)
                        }
                        .pickerStyle(.segmented)
                        if focus.locked {
                            slider("Position", value: lensPositionBinding,
                                   range: 0...1,
                                   readout: String(format: "%.2f",
                                                   focus.lensPosition))
                        }
                    }
                }

                Section {
                    Picker("Camera", selection: lensBinding) {
                        Text("None").tag("")
                        ForEach(streamer.availableLenses) { lens in
                            Text(lens.label).tag(lens.id)
                        }
                    }
                    Toggle("Use as default", isOn: $isDefault)
                } header: {
                    Text("Applies to")
                }
            }
            .navigationTitle(draft.name.isEmpty ? "New preset" : draft.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        // A nameless preset can't be told apart in the
                        // list, and an empty one would apply nothing.
                        .disabled(trimmedName.isEmpty || draft.isEmpty)
                }
            }
        }
        .navigationViewStyle(.stack)
        .tint(Theme.accent)
    }

    private var trimmedName: String {
        draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        draft.name = trimmedName
        manager.upsert(draft)
        if isDefault {
            manager.defaultPresetID = draft.id
        } else if manager.defaultPresetID == draft.id {
            manager.defaultPresetID = nil
        }
        dismiss()
    }

    private func fillFromCurrent() {
        let current = streamer.currentPresetValues()
        // Only the groups already included are overwritten: "fill" means
        // fill what this preset carries, not turn everything on.
        if draft.exposure != nil { draft.exposure = current.exposure }
        if draft.whiteBalance != nil { draft.whiteBalance = current.whiteBalance }
        if draft.zoom != nil { draft.zoom = current.zoom }
        if draft.focus != nil { draft.focus = current.focus }
        // A brand-new preset has nothing on yet, so fill would do nothing
        // and read as broken — take everything instead.
        if draft.isEmpty {
            draft.exposure = current.exposure
            draft.whiteBalance = current.whiteBalance
            draft.zoom = current.zoom
            draft.focus = current.focus
        }
    }

    // MARK: - Bindings
    //
    // Each group's toggle turns its optional on with the camera's current
    // values (so a freshly included group is never a meaningless zero) and
    // off by clearing it, which is what "not included" means on the wire.

    private var exposureIncluded: Binding<Bool> {
        Binding(get: { draft.exposure != nil },
                set: { draft.exposure = $0
                        ? streamer.currentPresetValues().exposure : nil })
    }
    private var whiteBalanceIncluded: Binding<Bool> {
        Binding(get: { draft.whiteBalance != nil },
                set: { draft.whiteBalance = $0
                        ? streamer.currentPresetValues().whiteBalance : nil })
    }
    private var zoomIncluded: Binding<Bool> {
        Binding(get: { draft.zoom != nil },
                set: { draft.zoom = $0
                        ? streamer.currentPresetValues().zoom : nil })
    }
    private var focusIncluded: Binding<Bool> {
        Binding(get: { draft.focus != nil },
                set: { draft.focus = $0
                        ? streamer.currentPresetValues().focus : nil })
    }

    private var exposureMode: Binding<Bool> {
        Binding(get: { draft.exposure?.manual ?? false },
                set: { draft.exposure?.manual = $0 })
    }
    private var whiteBalanceMode: Binding<Bool> {
        Binding(get: { draft.whiteBalance?.locked ?? false },
                set: { draft.whiteBalance?.locked = $0 })
    }
    private var focusMode: Binding<Bool> {
        Binding(get: { draft.focus?.locked ?? false },
                set: { draft.focus?.locked = $0 })
    }

    private var isoBinding: Binding<Double> {
        Binding(get: { Double(draft.exposure?.iso ?? 0) },
                set: { draft.exposure?.iso = Float($0) })
    }
    private var biasBinding: Binding<Double> {
        Binding(get: { Double(draft.exposure?.bias ?? 0) },
                set: { draft.exposure?.bias = Float($0) })
    }
    private var temperatureBinding: Binding<Double> {
        Binding(get: { Double(draft.whiteBalance?.temperature ?? 5000) },
                set: { draft.whiteBalance?.temperature = Float($0) })
    }
    private var zoomBinding: Binding<Double> {
        Binding(get: { draft.zoom ?? 1 }, set: { draft.zoom = $0 })
    }
    private var lensPositionBinding: Binding<Double> {
        Binding(get: { Double(draft.focus?.lensPosition ?? 0.5) },
                set: { draft.focus?.lensPosition = Float($0) })
    }
    private var lensBinding: Binding<String> {
        Binding(get: { draft.lensID ?? "" },
                set: { draft.lensID = $0.isEmpty ? nil : $0 })
    }

    /// Log scale, matching the Live screen's shutter row: shutter steps
    /// are multiplicative, and a linear slider crams everything usable
    /// into its first pixels.
    private var shutterBinding: Binding<Double> {
        let minSeconds = max(streamer.camera.minShutterSeconds, 1.0 / 8000)
        let maxSeconds = max(
            streamer.camera.maxShutterSeconds(fps: Int32(streamer.fps)),
            minSeconds * 2)
        let logMin = log(minSeconds)
        let logMax = log(maxSeconds)
        return Binding(
            get: {
                let seconds = min(max(draft.exposure?.shutterSeconds
                                        ?? minSeconds, minSeconds),
                                  maxSeconds)
                return 1 - (log(seconds) - logMin) / (logMax - logMin)
            },
            set: { position in
                draft.exposure?.shutterSeconds =
                    exp(logMax - position * (logMax - logMin))
            })
    }

    private var shutterReadout: String {
        let seconds = draft.exposure?.shutterSeconds ?? 0
        guard seconds > 0 else { return "—" }
        guard seconds < 1 else { return String(format: "%.0fs", seconds) }
        return "1/\(Int((1 / seconds).rounded()))"
    }

    private var isoRange: ClosedRange<Double> {
        let range = streamer.camera.isoRange
        return Double(range.lowerBound)...Double(range.upperBound)
    }
    private var biasRange: ClosedRange<Double> {
        let range = streamer.camera.exposureBiasRange
        return Double(range.lowerBound)...Double(range.upperBound)
    }

    /// Form-shaped slider row: label, slider, monospaced readout — the
    /// Live screen's anatomy (docs/UI_DESIGN.md §4) minus the icons,
    /// which have no room in a Form row.
    private func slider(_ label: String, value: Binding<Double>,
                        range: ClosedRange<Double>,
                        readout: String) -> some View {
        HStack {
            Text(label)
                .frame(width: 92, alignment: .leading)
            Slider(value: value, in: range)
            Text(readout)
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 56, alignment: .trailing)
        }
    }
}
