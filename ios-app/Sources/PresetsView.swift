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
                    editing = CameraPreset(name: "",
                                           lensID: streamer.selectedLens.id)
                }
            } header: {
                Text("Presets")
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
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack {
                Text(preset.name)
                if preset.id == manager.defaultPresetID {
                    Text("Default")
                        .font(.caption)
                        .padding(.horizontal, Theme.Space.s)
                        .padding(.vertical, Theme.Space.xs)
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
                        Picker("Exposure", selection: exposureMode) {
                            Text("AE").tag(false)
                            Text("Manual").tag(true)
                        }
                        .pickerStyle(.segmented)
                        if exposure.manual {
                            sliderRow("dial.min", "dial.max",
                                      value: isoBinding, range: isoRange,
                                      readout: "\(Int(draft.exposure?.iso ?? 0))")
                            sliderRow("tortoise", "hare",
                                      value: shutterBinding, range: 0...1,
                                      readout: shutterReadout)
                        } else {
                            sliderRow("sun.min", "sun.max",
                                      value: biasBinding, range: biasRange,
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
                        Picker("White balance", selection: whiteBalanceMode) {
                            Text("AWB").tag(false)
                            Text("Lock").tag(true)
                        }
                        .pickerStyle(.segmented)
                        if wb.locked {
                            // No icons, exactly as on the Live screen:
                            // the segmented control above names the row.
                            sliderRow(nil, nil,
                                      value: temperatureBinding,
                                      range: 2500...8000,
                                      readout: "\(Int(wb.temperature))K")
                        }
                    }
                }

                Section {
                    Toggle("Zoom", isOn: zoomIncluded)
                    if draft.zoom != nil {
                        sliderRow("minus.magnifyingglass",
                                  "plus.magnifyingglass",
                                  value: zoomBinding,
                                  range: 1...max(
                                    Double(streamer.camera.maxZoomFactor),
                                    1.1),
                                  readout: String(format: "%.1f×",
                                                  draft.zoom ?? 1))
                    }
                }

                Section {
                    Toggle("Focus", isOn: focusIncluded)
                    if let focus = draft.focus {
                        Picker("Focus", selection: focusMode) {
                            Text("AF").tag(false)
                            Text("Lock").tag(true)
                        }
                        .pickerStyle(.segmented)
                        if focus.locked {
                            sliderRow(nil, nil,
                                      value: lensPositionBinding,
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

    /// The product's slider row (docs/UI_DESIGN.md §4): leading icon ·
    /// slider · trailing icon · monospaced readout in a fixed 44 pt
    /// column. Same icons as the Live screen's rows, so a preset's
    /// exposure looks like the exposure you set live — the icons are
    /// dropped for white balance and focus, which have none there either.
    private func sliderRow(_ minIcon: String?, _ maxIcon: String?,
                           value: Binding<Double>,
                           range: ClosedRange<Double>,
                           readout: String) -> some View {
        HStack(spacing: Theme.Space.m) {
            if let minIcon {
                Image(systemName: minIcon).foregroundColor(.secondary)
            }
            Slider(value: value, in: range)
            if let maxIcon {
                Image(systemName: maxIcon).foregroundColor(.secondary)
            }
            Text(readout)
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }
}
