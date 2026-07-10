//
//  TelescopeSection.swift
//  AstroSky
//
//  The telescope block on an object's detail page: eyepiece preview, a
//  per-eyepiece comparison, difficulty, best time tonight, observing tips and
//  mount-specific finding steps.
//

import SwiftUI

struct TelescopeSection: View {
    @Environment(AppState.self) private var appState
    let object: any CelestialObject

    private var jd: Double { appState.skyJulianDate }
    private var angularSize: Double? {
        AngularSizeSource.angularSizeRadians(for: object, julianDate: jd)
    }

    /// Eyepiece currently driving the preview — the user's tapped choice, else
    /// the active eyepiece, else the first one.
    @State private var selectedEyepieceID: UUID?

    private var resolvedEyepiece: Eyepiece? {
        let eyepieces = appState.equipment.eyepieces
        if let id = selectedEyepieceID, let ep = eyepieces.first(where: { $0.id == id }) { return ep }
        return appState.equipment.activeEyepiece ?? eyepieces.first
    }

    var body: some View {
        if let scope = appState.equipment.activeTelescope, let eyepiece = resolvedEyepiece {
            let optics = TelescopeMath.result(scope: scope, eyepiece: eyepiece, bortleClass: appState.bortleClass)
            previewSection(optics: optics, eyepiece: eyepiece)
            eyepieceTable(scope: scope)
            tonightSection
            tipsSection(optics: optics)
            mountSection
        } else {
            Section("Telescope") {
                Text("Add your telescope and eyepieces to see what this looks like through the eyepiece, how hard it is, and how to find it.")
                    .font(.subheadline).foregroundStyle(.secondary)
                NavigationLink {
                    EquipmentEditorView()
                } label: {
                    Label("Set up my telescope", systemImage: "eyeglasses")
                }
            }
        }
    }

    @ViewBuilder
    private func previewSection(optics: OpticsResult, eyepiece: Eyepiece) -> some View {
        let assessment = TelescopeVisibility.assess(object: object, optics: optics,
                                                    angularSizeRadians: angularSize, bortleClass: appState.bortleClass)
        let telePhoto = ObjectImagery.telescopePhoto(for: object)
        let wideMatch = telePhoto?.caption == "Telescope view"
        Section {
            if let telePhoto {
                HStack(alignment: .top, spacing: 12) {
                    tile(caption: "Real photo") {
                        if wideMatch {
                            TelescopePhotoTile(photo: telePhoto, zoom: photoZoom(optics: optics))
                        } else {
                            ObjectPhotoView(key: telePhoto.key, subdir: telePhoto.subdir, maxPixel: 500)
                        }
                    }
                    tile(caption: "Eyepiece view") {
                        EyepiecePreviewView(object: object, optics: optics,
                                            angularSizeRadians: angularSize, bortleClass: appState.bortleClass,
                                            julianDate: jd)
                    }
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 6, trailing: 16))
            } else {
                EyepiecePreviewView(object: object, optics: optics,
                                    angularSizeRadians: angularSize, bortleClass: appState.bortleClass,
                                    julianDate: jd)
                    .frame(height: 260)
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets())
                    .padding(.vertical, 8)
            }
            HStack {
                Label(assessment.verdict.rawValue, systemImage: assessment.verdict.systemImage)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                eyepiecePicker(current: eyepiece)
            }
            Text(assessment.reason).font(.caption).foregroundStyle(.secondary)
        } header: {
            Text("Through the eyepiece")
        } footer: {
            if telePhoto != nil {
                Text(wideMatch
                     ? "Both show the same field of view at \(Int(optics.magnification))×: a real survey photo (left) and a simulation (right)."
                     : "Left: a real photograph. Right: a simulation of the eyepiece view.")
            }
        }
    }

    /// A tappable eyepiece switcher that drives the preview. Shown right by the
    /// preview so it's obvious you can change lenses.
    @ViewBuilder
    private func eyepiecePicker(current: Eyepiece) -> some View {
        Menu {
            ForEach(appState.equipment.eyepieces) { ep in
                Button {
                    selectedEyepieceID = ep.id
                } label: {
                    if ep.id == current.id {
                        Label(ep.name, systemImage: "checkmark")
                    } else {
                        Text(ep.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "eyeglasses")
                Text(current.name)
                Image(systemName: "chevron.up.chevron.down").font(.caption2)
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(.quaternary, in: Capsule())
        }
    }

    /// How much to crop the wide-field survey photo so it matches the eyepiece's
    /// true field of view (the cutout is framed to ~2.2× the object's size).
    private func photoZoom(optics: OpticsResult) -> CGFloat {
        let objectDegrees = (angularSize.map { $0 * 180 / .pi }) ?? 0.1
        let cutoutFOV = min(4.0, max(0.12, objectDegrees * 2.2))
        let eyepieceFOV = max(0.01, optics.trueFOVDegrees)
        return CGFloat(min(8.0, max(1.0, cutoutFOV / eyepieceFOV)))
    }

    /// A square, rounded tile with a small caption underneath.
    private func tile<Content: View>(caption: LocalizedStringKey,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 4) {
            content()
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(caption).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func eyepieceTable(scope: Telescope) -> some View {
        Section {
            ForEach(appState.equipment.eyepieces) { eyepiece in
                let optics = TelescopeMath.result(scope: scope, eyepiece: eyepiece, bortleClass: appState.bortleClass)
                let assessment = TelescopeVisibility.assess(object: object, optics: optics,
                                                            angularSizeRadians: angularSize, bortleClass: appState.bortleClass)
                let isSelected = eyepiece.id == resolvedEyepiece?.id
                Button {
                    selectedEyepieceID = eyepiece.id
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(eyepiece.name).foregroundStyle(.primary)
                            Text("\(Int(optics.magnification))× · \(optics.trueFOVDegrees, specifier: "%.2f")° field")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.indigo)
                        }
                        Image(systemName: assessment.verdict.systemImage)
                            .foregroundStyle(color(for: assessment.verdict))
                    }
                }
                .buttonStyle(.plain)
            }
            if appState.equipment.eyepieces.isEmpty {
                Text("Add an eyepiece to compare magnifications.").font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("With each of your eyepieces")
        } footer: {
            if !appState.equipment.eyepieces.isEmpty {
                Text("Tap an eyepiece to preview it above.")
            }
        }
    }

    @ViewBuilder private var tonightSection: some View {
        let placement = TonightPlacementCalculator.compute(object: object, observer: appState.observer, date: Date())
        if let best = placement.bestTime, placement.maxAltitudeDegrees > 0 {
            Section("Tonight") {
                LabeledContent("Best around", value: best.formatted(date: .omitted, time: .shortened))
                LabeledContent("Peak altitude", value: "\(Int(placement.maxAltitudeDegrees))°")
                if !placement.isWellPlaced {
                    Text("Stays fairly low tonight — a clear horizon helps.").font(.caption).foregroundStyle(.secondary)
                }
            }
        } else {
            Section("Tonight") {
                Text("Not well placed during tonight's dark hours from your location.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func tipsSection(optics: OpticsResult) -> some View {
        let tips = ObservingTips.tips(for: object, optics: optics)
        return Group {
            if !tips.isEmpty {
                Section("Observing tips") {
                    ForEach(Array(tips.enumerated()), id: \.offset) { _, tip in
                        Label(tip, systemImage: "lightbulb")
                            .font(.subheadline)
                    }
                }
            }
        }
    }

    private var mountSection: some View {
        let guidance = MountGuidanceGenerator.guidance(mount: appState.equipment.mountType,
                                                       object: object, julianDate: jd,
                                                       observer: appState.observer, catalog: appState.catalog)
        return Section("Find it · \(appState.equipment.mountType.displayName)") {
            ForEach(guidance.findSteps) { step in
                Label(step.text, systemImage: step.systemImage).font(.subheadline)
            }
            ForEach(guidance.settingCircles, id: \.label) { circle in
                LabeledContent(circle.label, value: circle.value)
            }
            if !guidance.alignmentStars.isEmpty {
                Text("Alignment stars up now: \(guidance.alignmentStars.map(\.name).joined(separator: ", "))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func color(for verdict: VisibilityAssessment.Verdict) -> Color {
        switch verdict {
        case .easy: .green
        case .visible: .mint
        case .challenging: .yellow
        case .notVisible: .secondary
        }
    }
}
