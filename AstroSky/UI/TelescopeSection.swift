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
    /// Pre-computed expensive results; nil while the initial computation is running.
    @State private var sectionData: SectionData?

    // MARK: - Memoized data

    private struct SectionData: Sendable {
        struct EyepieceRow: Identifiable, Sendable {
            var id: UUID { eyepieceID }
            let eyepieceID: UUID
            let eyepieceName: String
            let optics: OpticsResult
            let assessment: VisibilityAssessment
        }
        let eyepieceRows: [EyepieceRow]
        let placement: TonightPlacement
    }

    private var resolvedEyepiece: Eyepiece? {
        let eyepieces = appState.equipment.eyepieces
        if let id = selectedEyepieceID, let ep = eyepieces.first(where: { $0.id == id }) { return ep }
        return appState.equipment.activeEyepiece ?? eyepieces.first
    }

    /// Key for .task(id:). Excludes the selected eyepiece — every eyepiece row
    /// is pre-computed, so switching the picker is a free lookup, not a re-run.
    private var computeKey: String {
        let scopeID = appState.equipment.activeTelescope?.id.uuidString ?? "none"
        let allEPs = appState.equipment.eyepieces.map { $0.id.uuidString }.joined(separator: ",")
        let bortle = appState.bortleClass
        let lat = String(format: "%.2f", appState.observer.latitudeDegrees)
        return "\(object.id)|\(scopeID)|\(allEPs)|\(bortle)|\(lat)"
    }

    // MARK: - Body

    var body: some View {
        Group {
            if appState.equipment.activeTelescope != nil, let eyepiece = resolvedEyepiece {
                if let data = sectionData,
                   let activeRow = data.eyepieceRows.first(where: { $0.eyepieceID == eyepiece.id }) {
                    previewSection(optics: activeRow.optics, eyepiece: eyepiece,
                                   assessment: activeRow.assessment)
                    eyepieceTable(rows: data.eyepieceRows)
                    tonightSection(placement: data.placement)
                    tipsSection(optics: activeRow.optics)
                    mountSection
                } else {
                    Section("Telescope") {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Computing…").foregroundStyle(.secondary)
                        }
                    }
                }
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
        .task(id: computeKey) {
            guard let scope = appState.equipment.activeTelescope else {
                sectionData = nil
                return
            }
            let obj = object
            let eyepieces = appState.equipment.eyepieces
            let bortle = appState.bortleClass
            let angSz = angularSize
            let observer = appState.observer

            sectionData = await Task.detached(priority: .userInitiated) {
                let rows = eyepieces.map { ep -> SectionData.EyepieceRow in
                    let optics = TelescopeMath.result(scope: scope, eyepiece: ep, bortleClass: bortle)
                    let assessment = TelescopeVisibility.assess(object: obj, optics: optics,
                                                                angularSizeRadians: angSz,
                                                                bortleClass: bortle)
                    return SectionData.EyepieceRow(eyepieceID: ep.id, eyepieceName: ep.name,
                                                   optics: optics, assessment: assessment)
                }
                let placement = TonightPlacementCalculator.compute(object: obj, observer: observer,
                                                                    date: Date())
                return SectionData(eyepieceRows: rows, placement: placement)
            }.value
        }
    }

    // MARK: - Preview section

    @ViewBuilder
    private func previewSection(optics: OpticsResult, eyepiece: Eyepiece,
                                 assessment: VisibilityAssessment) -> some View {
        let telePhoto = ObjectImagery.telescopePhoto(for: object)
        let wideMatch = telePhoto?.caption == "Telescope view"
        Section {
            if let telePhoto {
                HStack(alignment: .top, spacing: 12) {
                    tile(caption: "Real photo") {
                        if wideMatch {
                            TelescopePhotoTile(photo: telePhoto, zoom: photoZoom())
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
                Text("Left: a real survey photo. Right: simulated eyepiece view at \(Int(optics.magnification))×.")
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

    /// Fixed zoom for the real-photo tile so it shows the object at a consistent
    /// scale regardless of which eyepiece is selected. The survey cutout is
    /// already framed to ~2.2× the object's angular size, so zoom=1 shows it
    /// at that natural framing; we stay at 1.0 unless the object is tiny.
    private func photoZoom() -> CGFloat {
        let objectDegrees = (angularSize.map { $0 * 180 / .pi }) ?? 0.1
        let cutoutFOV = min(4.0, max(0.12, objectDegrees * 2.2))
        // Use a fixed 1° reference instead of the eyepiece FOV so the photo
        // doesn't change when the user switches lenses.
        return CGFloat(min(4.0, max(1.0, cutoutFOV / 1.0)))
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

    // MARK: - Eyepiece comparison table

    private func eyepieceTable(rows: [SectionData.EyepieceRow]) -> some View {
        Section {
            ForEach(rows) { row in
                let isSelected = row.eyepieceID == resolvedEyepiece?.id
                Button {
                    selectedEyepieceID = row.eyepieceID
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.eyepieceName).foregroundStyle(.primary)
                            Text("\(Int(row.optics.magnification))× · \(row.optics.trueFOVDegrees, specifier: "%.2f")° field")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.indigo)
                        }
                        Image(systemName: row.assessment.verdict.systemImage)
                            .foregroundStyle(color(for: row.assessment.verdict))
                    }
                }
                .buttonStyle(.plain)
            }
            if rows.isEmpty {
                Text("Add an eyepiece to compare magnifications.").font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("With each of your eyepieces")
        } footer: {
            if !rows.isEmpty {
                Text("Tap an eyepiece to preview it above.")
            }
        }
    }

    // MARK: - Tonight section

    @ViewBuilder private func tonightSection(placement: TonightPlacement) -> some View {
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

    // MARK: - Tips & mount sections

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
