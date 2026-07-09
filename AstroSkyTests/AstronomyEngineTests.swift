//
//  AstronomyEngineTests.swift
//  AstroSkyTests
//
//  Fixture values come from Meeus, "Astronomical Algorithms", 2nd ed.
//  worked examples, so a regression here means real ephemeris breakage.
//

import Foundation
import Testing
@testable import AstroSky

struct TimeTests {
    @Test func julianDateOfJ2000() {
        var components = DateComponents()
        components.year = 2000; components.month = 1; components.day = 1
        components.hour = 12
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: components)!
        #expect(abs(AstroTime.julianDate(date) - 2_451_545.0) < 1e-6)
    }

    @Test func gmstMeeusExample12a() {
        // 1987 April 10, 0h UT → GMST 13h 10m 46.3668s = 197.693195°.
        let jd = 2_446_895.5
        let gmstDegrees = AstroTime.greenwichMeanSiderealTime(julianDate: jd) * AstroMath.radToDeg
        #expect(abs(gmstDegrees - 197.693195) < 0.0005)
    }

    @Test func julianDateRoundTrip() {
        let date = Date(timeIntervalSince1970: 1_752_000_000)
        let jd = AstroTime.julianDate(date)
        let back = AstroTime.date(julianDate: jd)
        #expect(abs(back.timeIntervalSince(date)) < 1e-3)
    }
}

struct CoordinateTests {
    @Test func obliquityAtJ2000() {
        let eps = CoordinateTransforms.meanObliquity(julianDate: AstroTime.j2000) * AstroMath.radToDeg
        #expect(abs(eps - 23.4392911) < 0.0001)
    }

    @Test func nutationMeeusExample22a() {
        // 1987 April 10, 0h TD: Δψ ≈ −3.788″, Δε ≈ +9.443″ (Meeus example 22.a).
        let jd = 2_446_895.5
        let nutation = Nutation.nutation(julianDate: jd)
        let arcsec = AstroMath.radToDeg * 3600.0
        #expect(abs(nutation.longitude * arcsec - (-3.788)) < 0.5)
        #expect(abs(nutation.obliquity * arcsec - 9.443) < 0.5)
    }

    @Test func keplerSolver() {
        let m = 60.0 * AstroMath.degToRad
        let e = 0.1
        let eAnom = AstroMath.solveKepler(meanAnomaly: m, eccentricity: e)
        #expect(abs(eAnom - e * sin(eAnom) - m) < 1e-10)
    }

    @Test func horizontalCoordinatesMeeusExample13b() {
        // Venus from the US Naval Observatory, 1987 April 10, 19:21 UT.
        // Meeus: azimuth 68.0337° (from south), altitude 15.1249°.
        let jd = 2_446_896.30625
        let venus = EquatorialCoordinates(raHours: 23.0 + 9.0 / 60.0 + 16.641 / 3600.0,
                                          decDegrees: -(6.0 + 43.0 / 60.0 + 11.61 / 3600.0))
        let observer = Observer(latitudeDegrees: 38.9213889, longitudeDegrees: -77.0655556)
        let horizontal = CoordinateTransforms.horizontal(of: venus, julianDate: jd, observer: observer)
        // Mean (not apparent) sidereal time costs a few hundredths of a degree.
        #expect(abs(horizontal.altitudeDegrees - 15.1249) < 0.05)
        #expect(abs(horizontal.azimuthDegrees - (68.0337 + 180.0)) < 0.05)
    }

    @Test func angularSeparationSiriusBetelgeuse() {
        let sirius = StarCatalog.starsByKey["sirius"]!.equatorialJ2000
        let betelgeuse = StarCatalog.starsByKey["betelgeuse"]!.equatorialJ2000
        let separation = CoordinateTransforms.angularSeparation(sirius, betelgeuse) * AstroMath.radToDeg
        #expect(separation > 26.0 && separation < 28.5)
    }

    @Test func refractionAtHorizon() {
        let r = CoordinateTransforms.refraction(trueAltitude: 0) * AstroMath.radToDeg
        #expect(r > 0.45 && r < 0.65)
    }

    @Test func precessionMovesPoleSlightly() {
        let polaris = EquatorialCoordinates(raHours: 2.5303, decDegrees: 89.2641)
        let in2026 = CoordinateTransforms.precessFromJ2000(polaris, julianDate: 2_461_041.0)
        let shift = CoordinateTransforms.angularSeparation(polaris, in2026) * AstroMath.radToDeg
        // Polaris precesses toward the pole by ~1/3° per quarter century.
        #expect(shift > 0.01 && shift < 1.0)
    }
}

struct SunMoonTests {
    @Test func sunPositionMeeusExample25a() {
        // 1992 October 13, 0h TD: geometric longitude ≈ 199.90988°,
        // distance ≈ 0.99766 AU.
        let jd = 2_448_908.5
        let sun = SunEphemeris.position(julianDate: jd)
        let longitudeDegrees = sun.ecliptic.longitude * AstroMath.radToDeg
        #expect(abs(longitudeDegrees - 199.90988) < 0.01)
        #expect(abs(sun.distanceAU - 0.99766) < 0.0005)
    }

    @Test func moonPositionMeeusExample47a() {
        // 1992 April 12, 0h TT: λ = 133.162655°, β = −3.229126°,
        // Δ = 368409.7 km (full series; ours is truncated).
        let jd = 2_448_724.5
        let moon = MoonEphemeris.position(julianDate: jd)
        let lambdaDegrees = moon.ecliptic.longitude * AstroMath.radToDeg
        let betaDegrees = moon.ecliptic.latitude * AstroMath.radToDeg
        #expect(abs(lambdaDegrees - 133.162655) < 0.05)
        #expect(abs(betaDegrees - (-3.229126)) < 0.03)
        #expect(abs(moon.distanceKm - 368_409.7) < 500)
    }

    @Test func moonPhaseIlluminationIsInRange() {
        let phase = MoonEphemeris.phase(julianDate: AstroTime.julianDate(Date()))
        #expect(phase.illuminatedFraction >= 0 && phase.illuminatedFraction <= 1)
        #expect(!phase.phaseName.isEmpty)
    }
}

struct PlanetTests {
    @Test func venusPositionMeeusExample33a() {
        // 1992 December 20, 0h TT: apparent α = 21h04m41.5s, δ = −18°53′17″.
        // With light-time, aberration and nutation applied we match to 0.05°.
        let jd = 2_448_976.5
        let position = PlanetEphemeris.position(of: .venus, julianDate: jd)
        let ofDate = CoordinateTransforms.precessFromJ2000(position.equatorialJ2000, julianDate: jd)
        let expected = EquatorialCoordinates(raHours: 21.0 + 4.0 / 60.0 + 41.5 / 3600.0,
                                             decDegrees: -(18.0 + 53.0 / 60.0 + 17.0 / 3600.0))
        let separation = CoordinateTransforms.angularSeparation(ofDate, expected) * AstroMath.radToDeg
        #expect(separation < 0.05)
        #expect(abs(position.distanceAU - 0.911) < 0.02)
    }

    @Test func planetDistancesAreSane() {
        let jd = AstroTime.julianDate(Date())
        for planet in Planet.visible {
            let position = PlanetEphemeris.position(of: planet, julianDate: jd)
            #expect(position.distanceAU > 0.2 && position.distanceAU < 32)
            #expect(position.magnitude > -6 && position.magnitude < 9)
        }
    }

    @Test func earthHeliocentricDistanceIsOneAU() {
        let jd = AstroTime.julianDate(Date())
        let earth = PlanetEphemeris.heliocentricPosition(of: .earth, julianDate: jd)
        let r = (earth.x * earth.x + earth.y * earth.y + earth.z * earth.z).squareRoot()
        #expect(abs(r - 1.0) < 0.02)
    }
}

struct EventsTests {
    private func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: c)!
    }

    @Test func nextFullMoonMatchesKnownInstant() {
        // The 2015-09-28 full Moon (the total-eclipse "supermoon") peaked at
        // ~02:50 UT. Searching from a week earlier must land within an hour.
        let start = utc(2015, 9, 21)
        let instants = EventsEngine.moonPhaseInstants(startingAt: start, days: 14, target: .pi)
        #expect(!instants.isEmpty)
        let known = utc(2015, 9, 28, 2, 50)
        let closest = instants.min { abs($0.timeIntervalSince(known)) < abs($1.timeIntervalSince(known)) }!
        #expect(abs(closest.timeIntervalSince(known)) < 3600)
    }

    @Test func fullMoonsAreOneSynodicMonthApart() {
        let instants = EventsEngine.moonPhaseInstants(startingAt: utc(2026, 1, 1), days: 90, target: .pi)
        #expect(instants.count >= 2)
        let gap = instants[1].timeIntervalSince(instants[0]) / 86_400
        #expect(abs(gap - 29.53) < 0.5)
    }

    @Test func perseidsActiveInMidAugust() {
        let active = MeteorShowers.active(on: utc(2026, 8, 12, 6))
        #expect(active.contains { $0.name == "Perseids" })
        let june = MeteorShowers.active(on: utc(2026, 6, 15))
        #expect(!june.contains { $0.name == "Perseids" })
    }
}

struct RiseSetTests {
    @Test func sunRisesAndSetsAtMidLatitudes() {
        var components = DateComponents()
        components.year = 2026; components.month = 7; components.day = 9
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let dayStart = calendar.date(from: components)!

        let observer = Observer(latitudeDegrees: 40.0, longitudeDegrees: -75.0)
        let twilight = RiseSetCalculator.twilight(observer: observer, startingAt: dayStart)
        #expect(twilight.sunrise != nil)
        #expect(twilight.sunset != nil)
        #expect(twilight.solarNoon != nil)
    }

    @Test func circumpolarStarNeverSets() {
        let observer = Observer(latitudeDegrees: 51.5, longitudeDegrees: 0)
        let polaris = StarCatalog.starsByKey["polaris"]!
        let events = RiseSetCalculator.events(startingAt: Date()) { date in
            polaris.horizontal(julianDate: AstroTime.julianDate(date), observer: observer).altitude
        }
        #expect(events.alwaysUp)
        #expect(!events.alwaysDown)
    }
}
