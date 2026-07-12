//
//  EventsEngineTests.swift
//  AstroSkyTests
//
//  Tests for EventsEngine: moon-phase scanning, conjunction detection,
//  meteor shower calendar, and eclipse geometry.
//

import Foundation
import Testing
@testable import AstroSky

// MARK: - Moon phases

struct MoonPhaseTests {
    private let midLatObs = Observer(latitudeDegrees: 40, longitudeDegrees: -74)

    @Test func fullMoonFoundInFifteenDayWindow() {
        // Start just before a known full moon and confirm we find exactly one.
        // JD 2460521 ≈ 2024-08-19 (known full moon).
        let start = AstroTime.date(julianDate: 2_460_519)   // 2 days before
        let instants = EventsEngine.moonPhaseInstants(startingAt: start, days: 5, target: .pi)
        #expect(!instants.isEmpty, "Should find at least one full moon in 5-day window")
        #expect(instants.count <= 2)
    }

    @Test func newMoonFoundInFifteenDayWindow() {
        // JD 2460505 ≈ 2024-08-04 (known new moon).
        let start = AstroTime.date(julianDate: 2_460_503)
        let instants = EventsEngine.moonPhaseInstants(startingAt: start, days: 5, target: 0)
        #expect(!instants.isEmpty, "Should find at least one new moon in 5-day window")
    }

    @Test func upcomingEventsContainMoonPhases() {
        let events = EventsEngine.upcoming(observer: midLatObs, startingAt: Date(), days: 30)
        let phaseKinds: Set<AstroEventKind> = [.fullMoon, .newMoon, .lunarEclipse, .solarEclipse]
        let hasMoonPhase = events.contains { phaseKinds.contains($0.kind) }
        #expect(hasMoonPhase, "30-day window should contain at least one moon phase event")
    }

    @Test func eventsAreSortedByDate() {
        let events = EventsEngine.upcoming(observer: midLatObs, startingAt: Date(), days: 30)
        for i in 1..<events.count {
            #expect(events[i - 1].date <= events[i].date,
                    "Events must be sorted chronologically")
        }
    }
}

// MARK: - Meteor showers

struct MeteorShowerTests {
    @Test func perseidsActiveInAugust() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var c = DateComponents(); c.year = 2024; c.month = 8; c.day = 12; c.hour = 12
        let peakDate = cal.date(from: c)!
        let active = MeteorShowers.active(on: peakDate)
        #expect(active.contains { $0.name == "Perseids" },
                "Perseids should be active on their peak date (Aug 12)")
    }

    @Test func geminidsActiveInDecember() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var c = DateComponents(); c.year = 2024; c.month = 12; c.day = 14; c.hour = 12
        let peakDate = cal.date(from: c)!
        let active = MeteorShowers.active(on: peakDate)
        #expect(active.contains { $0.name == "Geminids" },
                "Geminids should be active on their peak date (Dec 14)")
    }

    @Test func noShowersActiveInRandomDate() {
        // March 20 is well outside all major shower windows.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var c = DateComponents(); c.year = 2024; c.month = 3; c.day = 20; c.hour = 12
        let date = cal.date(from: c)!
        let active = MeteorShowers.active(on: date)
        #expect(active.isEmpty, "No major showers peak in mid-March")
    }

    @Test func perseidsEventAppearsInUpcoming() {
        // Scan from Jul 20 2026 — Perseids peak Aug 12, within 30 days.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var c = DateComponents(); c.year = 2026; c.month = 7; c.day = 20
        let start = cal.date(from: c)!
        let obs = Observer(latitudeDegrees: 40, longitudeDegrees: -74)
        let events = EventsEngine.upcoming(observer: obs, startingAt: start, days: 30)
        #expect(events.contains { $0.kind == .meteorShower && $0.title.contains("Perseids") },
                "Perseids should appear in the 30-day scan starting Jul 20")
    }

    @Test func allShowersHavePositiveZHR() {
        for shower in MeteorShowers.all {
            #expect(shower.zhr > 0, "Shower \(shower.name) must have zhr > 0")
        }
    }

    @Test func allShowersHaveValidRadiant() {
        for shower in MeteorShowers.all {
            #expect(shower.radiantRAHours >= 0 && shower.radiantRAHours < 24,
                    "\(shower.name) radiant RA must be in [0, 24)")
            #expect(shower.radiantDecDegrees >= -90 && shower.radiantDecDegrees <= 90,
                    "\(shower.name) radiant Dec must be in [−90, 90]")
        }
    }
}

// MARK: - Conjunction detection

struct ConjunctionTests {
    private let midLatObs = Observer(latitudeDegrees: 40, longitudeDegrees: -74)

    @Test func conjunctionsHaveTwoBodyTitle() {
        let events = EventsEngine.upcoming(observer: midLatObs, startingAt: Date(), days: 60)
        let conjunctions = events.filter { $0.kind == .conjunction }
        for conj in conjunctions {
            #expect(conj.title.contains("&"), "Conjunction title must contain '&': \(conj.title)")
            #expect(conj.title.hasSuffix("conjunction"),
                    "Conjunction title must end in 'conjunction': \(conj.title)")
        }
    }

    @Test func conjunctionDetailContainsDegrees() {
        let events = EventsEngine.upcoming(observer: midLatObs, startingAt: Date(), days: 60)
        for conj in events.filter({ $0.kind == .conjunction }) {
            #expect(conj.detail.contains("°"),
                    "Conjunction detail should contain degree symbol: \(conj.detail)")
        }
    }
}

// MARK: - Eclipse geometry

struct EclipseGeometryTests {
    @Test func elongationAtFullMoonIsNearPi() {
        // JD 2460521 ≈ 2024-08-19 full moon
        let elong = EventsEngine.moonSunElongation(julianDate: 2_460_521)
        #expect(abs(abs(elong) - .pi) < 0.1,
                "Moon–Sun elongation near full moon should be close to π, got \(elong)")
    }

    @Test func elongationAtNewMoonIsNearZero() {
        // JD 2460505 ≈ 2024-08-04 new moon
        let elong = EventsEngine.moonSunElongation(julianDate: 2_460_505)
        #expect(abs(elong) < 0.2,
                "Moon–Sun elongation near new moon should be close to 0, got \(elong)")
    }
}
