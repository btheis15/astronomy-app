//
//  ObserveTonightView.swift
//  AstroSky
//
//  "What can my telescope see tonight" — filters the catalog to objects your
//  active scope can realistically show that are well-placed during tonight's
//  dark hours, sorted easiest-first.
//

import SwiftUI

struct ObserveTonightView: View {
    @Environment(AppState.self) private var appState
    @State private var targets: [Target] = []
    @State private var loaded = false

    struct Target: Identifiable {
        let object: any CelestialObject
        let verdict: VisibilityAssessment.Verdict
        let maxAltitude: Double
        let bestTime: Date?
        var id: String { object.id }
    }

    var body: some View {
        List {
            if appState.activeOptics == nil {
                Section {
                    NavigationLink { EquipmentEditorView() } label: {
                        Label("Set up my telescope first", systemImage: "eyeglasses")
                    }
                }
            }
            if !loaded {
                Section { HStack { ProgressView(); Text("Finding tonight's targets…").foregroundStyle(.secondary) } }
            } else if targets.isEmpty {
                Section {
                    ContentUnavailableView("Nothing well-placed",
                                           systemImage: "moon.zzz",
                                           description: Text("No catalog targets are both within your scope's reach and high enough tonight."))
                }
            } else {
                ForEach(targets) { target in
                    NavigationLink {
                        ObjectDetailView(object: target.object)
                    } label: {
                        row(target)
                    }
                }
            }
        }
        .navigationTitle("Observe Tonight")
        .task { if !loaded { await load() } }
    }

    private func row(_ target: Target) -> some View {
        HStack {
            Image(systemName: target.object.kind.iconSystemName).foregroundStyle(.yellow).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(target.object.name)
                Text(target.object.subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(target.verdict.rawValue).font(.caption.weight(.semibold))
                if let best = target.bestTime {
                    Text(best.formatted(date: .omitted, time: .shortened))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func load() async {
        let optics = appState.activeOptics
        let bortle = appState.bortleClass
        let observer = appState.observer
        let now = Date()

        // Candidate pool: solar system, minor bodies, deep sky (skip stars — too many).
        var candidates: [any CelestialObject] = [appState.catalog.sun, appState.catalog.moon]
        candidates.append(contentsOf: appState.catalog.planets.map { $0 as any CelestialObject })
        candidates.append(contentsOf: appState.catalog.minorBodies.map { $0 as any CelestialObject })
        candidates.append(contentsOf: appState.catalog.deepSky.map { $0 as any CelestialObject })
        candidates.removeAll { $0.kind == .sun }   // never a night target
        // Some objects appear in more than one catalog (e.g. Caldwell 20 is the
        // same North America Nebula as NGC 7000); show each physical object once.
        var seenNames = Set<String>()
        candidates = candidates.filter { seenNames.insert($0.name.lowercased()).inserted }

        let jd = appState.skyJulianDate
        var result: [Target] = []
        for object in candidates {
            let placement = TonightPlacementCalculator.compute(object: object, observer: observer, date: now)
            guard placement.isWellPlaced else { continue }
            let verdict: VisibilityAssessment.Verdict
            if let optics {
                let size = AngularSizeSource.angularSizeRadians(for: object, julianDate: jd)
                verdict = TelescopeVisibility.assess(object: object, optics: optics,
                                                     angularSizeRadians: size, bortleClass: bortle).verdict
            } else {
                verdict = .visible
            }
            guard verdict != .notVisible else { continue }
            result.append(Target(object: object, verdict: verdict,
                                  maxAltitude: placement.maxAltitudeDegrees, bestTime: placement.bestTime))
        }
        // Easiest first, then highest.
        let order: [VisibilityAssessment.Verdict] = [.easy, .visible, .challenging, .notVisible]
        targets = result.sorted {
            let a = order.firstIndex(of: $0.verdict) ?? 9
            let b = order.firstIndex(of: $1.verdict) ?? 9
            return a != b ? a < b : $0.maxAltitude > $1.maxAltitude
        }
        loaded = true
    }
}
