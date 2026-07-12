//
//  TonightPlanner.swift
//  AstroSky
//
//  Shared "tonight's best targets for your telescope" computation.
//  Used by TonightView (top-5 preview) and ObserveTonightView (full list).
//

import Foundation

/// A single telescope target for tonight's planning session.
struct TonightTarget: Identifiable, Sendable {
    let object: any CelestialObject
    let verdict: VisibilityAssessment.Verdict
    let maxAltitude: Double
    let bestTime: Date?
    var id: String { object.id }
}

/// Computes tonight's ranked telescope targets off the main actor.
@MainActor
enum TonightPlanner {
    static func compute(appState: AppState) async -> [TonightTarget] {
        let optics = appState.activeOptics
        let bortle = appState.bortleClass
        let bortleLimit = appState.bortleLimitingMagnitude
        let observer = appState.observer
        let now = Date()
        let jd = appState.skyJulianDate

        var candidates: [any CelestialObject] = [appState.catalog.moon]
        candidates.append(contentsOf: appState.catalog.planets.map { $0 as any CelestialObject })
        candidates.append(contentsOf: appState.catalog.minorBodies.map { $0 as any CelestialObject })
        if optics != nil {
            candidates.append(contentsOf: appState.catalog.deepSky.map { $0 as any CelestialObject })
        }
        var seenNames = Set<String>()
        candidates = candidates.filter { seenNames.insert($0.name.lowercased()).inserted }

        return await Task.detached(priority: .userInitiated) { () -> [TonightTarget] in
            var result: [TonightTarget] = []
            for object in candidates {
                let placement = TonightPlacementCalculator.compute(object: object,
                                                                    observer: observer,
                                                                    date: now)
                guard placement.isWellPlaced else { continue }
                let verdict: VisibilityAssessment.Verdict
                if let optics {
                    let size = AngularSizeSource.angularSizeRadians(for: object, julianDate: jd)
                    verdict = TelescopeVisibility.assess(object: object, optics: optics,
                                                         angularSizeRadians: size,
                                                         bortleClass: bortle).verdict
                } else {
                    // No telescope — only include solar system objects and
                    // naked-eye stars (magnitude within the Bortle sky limit).
                    switch object.kind {
                    case .planet, .moon, .minorBody:
                        verdict = .visible
                    case .star:
                        guard (object.magnitude ?? 99) <= bortleLimit else { continue }
                        verdict = .visible
                    default:
                        continue
                    }
                }
                guard verdict != .notVisible else { continue }
                result.append(TonightTarget(object: object, verdict: verdict,
                                            maxAltitude: placement.maxAltitudeDegrees,
                                            bestTime: placement.bestTime))
            }
            let order: [VisibilityAssessment.Verdict] = [.easy, .visible, .challenging, .notVisible]
            return result.sorted {
                let a = order.firstIndex(of: $0.verdict) ?? 9
                let b = order.firstIndex(of: $1.verdict) ?? 9
                return a != b ? a < b : $0.maxAltitude > $1.maxAltitude
            }
        }.value
    }
}
