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

    var body: some View {
        if let optics = appState.activeOptics, let scope = appState.equipment.activeTelescope {
            previewSection(optics: optics)
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

    private func previewSection(optics: OpticsResult) -> some View {
        let assessment = TelescopeVisibility.assess(object: object, optics: optics,
                                                    angularSizeRadians: angularSize, bortleClass: appState.bortleClass)
        return Section("Through the eyepiece") {
            EyepiecePreviewView(object: object, optics: optics,
                                angularSizeRadians: angularSize, bortleClass: appState.bortleClass)
                .frame(height: 260)
                .listRowInsets(EdgeInsets())
                .padding(.vertical, 8)
            HStack {
                Label(assessment.verdict.rawValue, systemImage: assessment.verdict.systemImage)
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            Text(assessment.reason).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func eyepieceTable(scope: Telescope) -> some View {
        Section("With each of your eyepieces") {
            ForEach(appState.equipment.eyepieces) { eyepiece in
                let optics = TelescopeMath.result(scope: scope, eyepiece: eyepiece, bortleClass: appState.bortleClass)
                let assessment = TelescopeVisibility.assess(object: object, optics: optics,
                                                            angularSizeRadians: angularSize, bortleClass: appState.bortleClass)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(eyepiece.name)
                        Text("\(Int(optics.magnification))× · \(optics.trueFOVDegrees, specifier: "%.2f")° field")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: assessment.verdict.systemImage)
                        .foregroundStyle(color(for: assessment.verdict))
                }
            }
            if appState.equipment.eyepieces.isEmpty {
                Text("Add an eyepiece to compare magnifications.").font(.caption).foregroundStyle(.secondary)
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
