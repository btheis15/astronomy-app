//
//  EquipmentEditorView.swift
//  AstroSky
//
//  Manage saved telescopes, eyepieces and mount type — written for beginners,
//  with plain-language help on every field and one-tap starter presets.
//

import SwiftUI

struct EquipmentEditorView: View {
    @Environment(AppState.self) private var appState
    @State private var addingTelescope = false
    @State private var addingEyepiece = false

    var body: some View {
        Form {
            mountSection
            telescopeSection
            eyepieceSection

            if appState.equipment.telescopes.isEmpty && appState.equipment.eyepieces.isEmpty {
                Section {
                    Text("New to telescopes? Tap “Add” above and pick a preset that looks like your gear — you can fine-tune the numbers afterward.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Telescope Equipment")
        .sheet(isPresented: $addingTelescope) { AddTelescopeSheet() }
        .sheet(isPresented: $addingEyepiece) { AddEyepieceSheet() }
    }

    private var mountSection: some View {
        Section {
            Picker("Mount type", selection: Binding(
                get: { appState.equipment.mountType },
                set: { appState.setMountType($0) })) {
                ForEach(MountType.allCases) { Text($0.displayName).tag($0) }
            }
            Text(appState.equipment.mountType.beginnerDescription)
                .font(.footnote).foregroundStyle(.secondary)
        } header: {
            Text("Mount")
        } footer: {
            Text(EquipmentHelp.mountIntro)
        }
    }

    private var telescopeSection: some View {
        Section {
            ForEach(appState.equipment.telescopes) { scope in
                Button {
                    appState.setActiveTelescope(scope.id)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(scope.name).foregroundStyle(.primary)
                            Text("f=\(Int(scope.focalLengthMM))mm · ⌀\(Int(scope.apertureMM))mm · f/\(scope.focalRatio, specifier: "%.1f")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if scope.id == appState.equipment.activeTelescopeID {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.indigo)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete { $0.map { appState.equipment.telescopes[$0].id }.forEach(appState.deleteTelescope) }
            Button { addingTelescope = true } label: { Label("Add telescope", systemImage: "plus") }
        } header: {
            Text("Telescopes")
        }
    }

    private var eyepieceSection: some View {
        Section {
            ForEach(appState.equipment.eyepieces) { eyepiece in
                Button {
                    appState.setActiveEyepiece(eyepiece.id)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(eyepiece.name).foregroundStyle(.primary)
                            Text("\(Int(eyepiece.focalLengthMM))mm · \(Int(eyepiece.apparentFOVDegrees))° AFOV")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if eyepiece.id == appState.equipment.activeEyepieceID {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.indigo)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete { $0.map { appState.equipment.eyepieces[$0].id }.forEach(appState.deleteEyepiece) }
            Button { addingEyepiece = true } label: { Label("Add eyepiece", systemImage: "plus") }
        } header: {
            Text("Eyepieces")
        }
    }
}

// MARK: - Add telescope

private struct AddTelescopeSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var focal = ""
    @State private var aperture = ""

    private var valid: Bool {
        (Double(focal) ?? 0) > 0 && (Double(aperture) ?? 0) > 0 && !name.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Start from a preset") {
                    ForEach(EquipmentHelp.telescopePresets) { preset in
                        Button(preset.name) {
                            name = preset.name
                            focal = String(Int(preset.focalLengthMM))
                            aperture = String(Int(preset.apertureMM))
                        }
                    }
                }
                Section {
                    TextField("Name (e.g. My Dobsonian)", text: $name)
                } header: { Text("Name") }
                Section {
                    TextField("Focal length (mm)", text: $focal).keyboardType(.numberPad)
                } footer: { Text(EquipmentHelp.scopeFocalLength) }
                Section {
                    TextField("Aperture (mm)", text: $aperture).keyboardType(.numberPad)
                } footer: { Text(EquipmentHelp.aperture) }
            }
            .navigationTitle("Add Telescope")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        appState.addTelescope(Telescope(name: name,
                                                        focalLengthMM: Double(focal) ?? 0,
                                                        apertureMM: Double(aperture) ?? 0))
                        dismiss()
                    }.disabled(!valid)
                }
            }
        }
    }
}

// MARK: - Add eyepiece

private struct AddEyepieceSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var focal = ""
    @State private var afov = "52"

    private var valid: Bool { (Double(focal) ?? 0) > 0 && !name.isEmpty }

    /// Live magnification preview against the active scope, if any.
    private var previewLine: String? {
        guard let scope = appState.equipment.activeTelescope, let fl = Double(focal), fl > 0 else { return nil }
        let mag = scope.focalLengthMM / fl
        let exitPupil = scope.apertureMM / mag
        return "≈ \(Int(mag))× with your \(scope.name) — \(EquipmentHelp.exitPupilNote(exitPupil))."
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Start from a preset") {
                    ForEach(EquipmentHelp.eyepiecePresets) { preset in
                        Button(preset.name) {
                            name = preset.name
                            focal = String(Int(preset.focalLengthMM))
                            afov = String(Int(preset.apparentFOVDegrees))
                        }
                    }
                }
                Section {
                    TextField("Name (e.g. 25mm Plössl)", text: $name)
                } header: { Text("Name") }
                Section {
                    TextField("Focal length (mm)", text: $focal).keyboardType(.numberPad)
                } footer: { Text(EquipmentHelp.eyepieceFocalLength) }
                Section {
                    TextField("Apparent field of view (°)", text: $afov).keyboardType(.numberPad)
                } footer: { Text(EquipmentHelp.apparentFOV) }
                if let previewLine {
                    Section { Text(previewLine).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Add Eyepiece")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        appState.addEyepiece(Eyepiece(name: name,
                                                      focalLengthMM: Double(focal) ?? 0,
                                                      apparentFOVDegrees: Double(afov) ?? 52))
                        dismiss()
                    }.disabled(!valid)
                }
            }
        }
    }
}
