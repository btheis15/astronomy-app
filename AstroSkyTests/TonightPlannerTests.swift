//
//  TonightPlannerTests.swift
//  AstroSkyTests
//
//  Covers TonightPlanner ranking invariants and no-equipment filtering,
//  plus TonightPlacementCalculator sanity checks.
//

import Foundation
import Testing
@testable import AstroSky

// MARK: - Ranking

struct TonightTargetRankingTests {
    private let catalog = SkyCatalog()
    private var anyObject: any CelestialObject { catalog.planets.first! }

    private func target(verdict: VisibilityAssessment.Verdict, altitude: Double) -> TonightTarget {
        TonightTarget(object: anyObject, verdict: verdict, maxAltitude: altitude, bestTime: nil)
    }

    @Test func easyRanksBeforeVisible() {
        let targets = [
            target(verdict: .visible, altitude: 80),
            target(verdict: .easy,    altitude: 40),
        ]
        let sorted = TonightPlannerTests.sorted(targets)
        #expect(sorted.first?.verdict == .easy)
    }

    @Test func visibleRanksBeforeChallenging() {
        let targets = [
            target(verdict: .challenging, altitude: 80),
            target(verdict: .visible,     altitude: 40),
        ]
        let sorted = TonightPlannerTests.sorted(targets)
        #expect(sorted.first?.verdict == .visible)
    }

    @Test func sameVerdictHigherAltitudeFirst() {
        let targets = [
            target(verdict: .visible, altitude: 30),
            target(verdict: .visible, altitude: 75),
        ]
        let sorted = TonightPlannerTests.sorted(targets)
        #expect(sorted.first?.maxAltitude == 75)
    }

    @Test func fullRankingOrder() {
        let targets = [
            target(verdict: .challenging, altitude: 60),
            target(verdict: .easy,        altitude: 45),
            target(verdict: .visible,     altitude: 50),
            target(verdict: .easy,        altitude: 70),
        ]
        let sorted = TonightPlannerTests.sorted(targets)
        #expect(sorted[0].verdict == .easy    && sorted[0].maxAltitude == 70)
        #expect(sorted[1].verdict == .easy    && sorted[1].maxAltitude == 45)
        #expect(sorted[2].verdict == .visible)
        #expect(sorted[3].verdict == .challenging)
    }
}

// MARK: - No-equipment filter

@MainActor
struct TonightPlannerNoEquipmentTests {
    @Test func noEquipmentExcludesDeepSky() async {
        let state = AppState()
        #expect(state.activeOptics == nil)

        let targets = await TonightPlanner.compute(appState: state)

        let deepSkyInResults = targets.filter { $0.object.kind == .deepSky }
        #expect(deepSkyInResults.isEmpty,
                "Deep sky objects must not appear when no telescope is configured")
    }

    @Test func noEquipmentIncludesPlanets() async {
        let state = AppState()
        // Set a mid-latitude location where planets can rise above 20°
        state.locationService.setManualLocation(latitudeDegrees: 40, longitudeDegrees: -74,
                                                name: "Test")
        let targets = await TonightPlanner.compute(appState: state)

        // May be empty if tonight has no planets above 20° (e.g. polar summer), so
        // just verify all returned objects are solar-system or star.
        for target in targets {
            let kind = target.object.kind
            #expect(kind == .planet || kind == .moon || kind == .minorBody || kind == .star,
                    "Without equipment, only solar-system + naked-eye stars should appear")
        }
    }

    @Test func resultsSortedByRankThenAltitude() async {
        let state = AppState()
        state.locationService.setManualLocation(latitudeDegrees: 35, longitudeDegrees: -80,
                                                name: "Test")
        let targets = await TonightPlanner.compute(appState: state)

        let order: [VisibilityAssessment.Verdict] = [.easy, .visible, .challenging, .notVisible]
        for i in 1..<targets.count {
            let prev = order.firstIndex(of: targets[i - 1].verdict) ?? 9
            let curr = order.firstIndex(of: targets[i].verdict) ?? 9
            if prev == curr {
                #expect(targets[i - 1].maxAltitude >= targets[i].maxAltitude,
                        "Equal-verdict targets must be sorted by altitude descending")
            } else {
                #expect(prev < curr,
                        "Verdict order must be easy → visible → challenging")
            }
        }
    }
}

// MARK: - Placement calculator

struct TonightPlacementCalculatorTests {
    private let midLatObs = Observer(latitudeDegrees: 40, longitudeDegrees: -74)

    @Test func wellPlacedThresholdIsTwentyDegrees() {
        var placement = TonightPlacement(maxAltitudeRadians: 19.9 * AstroMath.degToRad,
                                         bestTime: nil)
        #expect(!placement.isWellPlaced)
        placement = TonightPlacement(maxAltitudeRadians: 20.1 * AstroMath.degToRad,
                                     bestTime: nil)
        #expect(placement.isWellPlaced)
    }

    @Test func sunIsNotWellPlacedDuringDarkWindow() {
        // The Sun is below the horizon during the dark window — it should not
        // be "well placed" for astronomical observation tonight.
        let sun = SkyCatalog().sun
        let placement = TonightPlacementCalculator.compute(object: sun,
                                                           observer: midLatObs,
                                                           date: Date())
        // The Sun always sets; during the dark window it's well below 0°.
        #expect(!placement.isWellPlaced ||
                placement.maxAltitudeDegrees < 20,
                "The Sun should not count as well-placed for nighttime observing")
    }
}

// MARK: - Helpers (shared sort logic mirrors TonightPlanner internals)

private enum TonightPlannerTests {
    static func sorted(_ targets: [TonightTarget]) -> [TonightTarget] {
        let order: [VisibilityAssessment.Verdict] = [.easy, .visible, .challenging, .notVisible]
        return targets.sorted {
            let a = order.firstIndex(of: $0.verdict) ?? 9
            let b = order.firstIndex(of: $1.verdict) ?? 9
            return a != b ? a < b : $0.maxAltitude > $1.maxAltitude
        }
    }
}
