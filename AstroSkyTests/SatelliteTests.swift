//
//  SatelliteTests.swift
//  AstroSkyTests
//

import Foundation
import Testing
import UserNotifications
@testable import AstroSky

/// The classic ISS reference TLE (2008-09-20 epoch) with valid checksums.
private let issName = "ISS (ZARYA)"
private let issLine1 = "1 25544U 98067A   08264.51782528 -.00002182  00000-0 -11606-4 0  2927"
private let issLine2 = "2 25544  51.6416 247.4627 0006703 130.5360 325.0288 15.72125391563537"

struct TLEParserTests {
    @Test func parsesReferenceISSTLE() throws {
        let tle = try TLEParser.parse(name: issName, line1: issLine1, line2: issLine2)
        #expect(tle.catalogNumber == 25544)
        #expect(abs(tle.inclination * AstroMath.radToDeg - 51.6416) < 1e-4)
        #expect(abs(tle.raan * AstroMath.radToDeg - 247.4627) < 1e-4)
        #expect(abs(tle.eccentricity - 0.0006703) < 1e-7)
        #expect(abs(tle.argumentOfPerigee * AstroMath.radToDeg - 130.5360) < 1e-4)
        #expect(abs(tle.meanAnomaly * AstroMath.radToDeg - 325.0288) < 1e-4)
        #expect(abs(tle.meanMotionRevPerDay - 15.72125391) < 1e-8)
        #expect(abs(tle.bstar - (-0.11606e-4)) < 1e-9)
        #expect(tle.isNearEarth)

        // Epoch: 2008, day 264.51782528 → 2008-09-20 ≈ 12:25:40 UTC.
        // JD of 2008-01-01 00:00 = 2454466.5; day-of-year is 1-based.
        let expectedEpoch = 2_454_466.5 + 264.51782528 - 1.0
        #expect(abs(tle.epochJD - expectedEpoch) < 1e-6)
    }

    @Test func checksumValidation() {
        #expect(TLEParser.computedChecksum(issLine1) == 7)
        #expect(TLEParser.computedChecksum(issLine2) == 7)

        var corrupted = issLine1
        let index = corrupted.index(corrupted.startIndex, offsetBy: 20)
        corrupted.replaceSubrange(index...index, with: "9")
        #expect(throws: TLEError.self) {
            _ = try TLEParser.parse(name: issName, line1: corrupted, line2: issLine2)
        }
    }

    @Test func parsesTextBlob() {
        let blob = """
        \(issName)
        \(issLine1)
        \(issLine2)
        """
        let tles = TLEParser.parse(text: blob)
        #expect(tles.count == 1)
        #expect(tles.first?.name == issName)
    }

    @Test func assumedDecimalExponentField() {
        #expect(abs(TLEParser.parseAssumedDecimalExponent("-11606-4") - (-0.11606e-4)) < 1e-12)
        #expect(abs(TLEParser.parseAssumedDecimalExponent(" 36258-4") - 0.36258e-4) < 1e-12)
        #expect(TLEParser.parseAssumedDecimalExponent(" 00000-0") == 0)
        #expect(TLEParser.parseAssumedDecimalExponent("") == 0)
    }
}

struct SGP4Tests {
    private func makePropagator() throws -> SGP4 {
        let tle = try TLEParser.parse(name: issName, line1: issLine1, line2: issLine2)
        return try SGP4(tle: tle)
    }

    @Test func stateAtEpochIsLEO() throws {
        let sgp4 = try makePropagator()
        let state = try sgp4.propagate(minutesSinceEpoch: 0)
        let r = (state.position.x * state.position.x
            + state.position.y * state.position.y
            + state.position.z * state.position.z).squareRoot()
        let v = (state.velocity.x * state.velocity.x
            + state.velocity.y * state.velocity.y
            + state.velocity.z * state.velocity.z).squareRoot()
        // ISS: ~6,720 km geocentric radius, ~7.66 km/s.
        #expect(r > 6_600 && r < 6_850)
        #expect(v > 7.4 && v < 7.9)
    }

    @Test func orbitReturnsAfterOnePeriod() throws {
        let sgp4 = try makePropagator()
        let period = sgp4.tle.periodMinutes
        let s0 = try sgp4.propagate(minutesSinceEpoch: 0)
        let s1 = try sgp4.propagate(minutesSinceEpoch: period)
        let dx = s1.position - s0.position
        let drift = (dx.x * dx.x + dx.y * dx.y + dx.z * dx.z).squareRoot()
        // After one orbit the satellite should be back nearby (J2 nodal
        // regression and drag cause a small offset).
        #expect(drift < 500)
    }

    @Test func altitudeStaysInBandOverOneDay() throws {
        let sgp4 = try makePropagator()
        for minutes in stride(from: 0.0, through: 1_440.0, by: 10.0) {
            let state = try sgp4.propagate(minutesSinceEpoch: minutes)
            let r = (state.position.x * state.position.x
                + state.position.y * state.position.y
                + state.position.z * state.position.z).squareRoot()
            #expect(r > 6_550 && r < 6_900, "radius \(r) km at t=\(minutes) min")
        }
    }

    @Test func deepSpaceOrbitIsRejected() {
        // A 12-hour Molniya-like orbit must be refused by the near-earth
        // propagator (period ≥ 225 min).
        var tle = TLE(name: "FAKE MOLNIYA", catalogNumber: 99999,
                      epochJD: 2_460_000.5,
                      inclination: 63.4 * AstroMath.degToRad,
                      raan: 0, eccentricity: 0.7,
                      argumentOfPerigee: 4.7, meanAnomaly: 0,
                      meanMotionRevPerDay: 2.0, bstar: 0)
        #expect(throws: SGP4Error.self) {
            _ = try SGP4(tle: tle)
        }
        tle.meanMotionRevPerDay = 15.0
        #expect(tle.isNearEarth)
    }
}

struct SatelliteGeometryTests {
    @Test func observerECEFAtEquatorAndPole() {
        let equator = Satellite.geodeticToECEF(Observer(latitudeDegrees: 0, longitudeDegrees: 0))
        #expect(abs(equator.x - 6_378.137) < 0.01)
        #expect(abs(equator.y) < 0.01)
        #expect(abs(equator.z) < 0.01)

        let pole = Satellite.geodeticToECEF(Observer(latitudeDegrees: 90, longitudeDegrees: 0))
        #expect(abs(pole.z - 6_356.752) < 0.01)   // polar radius
        #expect(abs(pole.x) < 0.01)
    }

    @Test func issOverheadMagnitudeInRange() {
        // A near-overhead ISS pass (~450 km range) at roughly half phase should
        // land in the naked-eye-bright range of about −4 to −1.
        let mag = Satellite.estimatedMagnitude(standardMagnitude: -1.8,
                                               rangeKm: 450,
                                               illuminatedFraction: 0.5)
        #expect(mag > -4 && mag < -1)
    }

    @Test func brighterWhenCloserAndMoreLit() {
        let far = Satellite.estimatedMagnitude(standardMagnitude: -1.8, rangeKm: 1500, illuminatedFraction: 0.5)
        let near = Satellite.estimatedMagnitude(standardMagnitude: -1.8, rangeKm: 450, illuminatedFraction: 0.5)
        let fuller = Satellite.estimatedMagnitude(standardMagnitude: -1.8, rangeKm: 450, illuminatedFraction: 1.0)
        #expect(near < far)          // closer ⇒ brighter (smaller magnitude)
        #expect(fuller < near)       // more illuminated ⇒ brighter
    }

    @Test func sunlitTestBasicGeometry() {
        let jd = 2_460_000.5
        let sunDir = SunEphemeris.position(julianDate: jd).equatorial.unitVector
        // A satellite between the Earth and the Sun is sunlit…
        let dayside = sunDir * 7_000.0
        #expect(Satellite.isSunlit(temePosition: dayside, julianDate: jd))
        // …one directly behind the Earth at LEO altitude is in shadow.
        let nightside = sunDir * -7_000.0
        #expect(!Satellite.isSunlit(temePosition: nightside, julianDate: jd))
    }
}

struct PassNotificationTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func pass(startOffset: TimeInterval, visible: Bool, id: String = "sat.25544") -> SatellitePass {
        SatellitePass(satelliteID: id, satelliteName: "ISS",
                      start: now.addingTimeInterval(startOffset),
                      peak: now.addingTimeInterval(startOffset + 60),
                      end: now.addingTimeInterval(startOffset + 120),
                      maxAltitude: 1.0, isVisible: visible, peakMagnitude: -2.0)
    }

    @Test func schedulesForFavoritedPassElevenMinutesAway() {
        let requests = PassNotifications.requests(for: [pass(startOffset: 11 * 60, visible: true)], now: now)
        #expect(requests.count == 1)
        let trigger = requests.first?.trigger as? UNTimeIntervalNotificationTrigger
        // Fires ~1 minute from now (11 min start − 10 min lead time).
        #expect(trigger != nil)
        #expect((trigger?.timeInterval ?? 0) > 30 && (trigger?.timeInterval ?? 0) < 120)
    }

    @Test func skipsPastAndInvisiblePasses() {
        let past = pass(startOffset: 60, visible: true)          // fire time already elapsed
        let invisible = pass(startOffset: 3600, visible: false, id: "sat.999")
        #expect(PassNotifications.requests(for: [past, invisible], now: now).isEmpty)
    }

    @Test func capsPendingCount() {
        let many = (0..<40).map { pass(startOffset: Double(700 + $0 * 600), visible: true, id: "sat.\($0)") }
        #expect(PassNotifications.requests(for: many, now: now).count <= PassNotifications.maxPending)
    }
}

struct CatalogIntegrityTests {
    @Test func starKeysAreUnique() {
        var seen = Set<String>()
        for star in StarCatalog.stars {
            #expect(!seen.contains(star.key), "duplicate star key \(star.key)")
            seen.insert(star.key)
        }
    }

    @Test func constellationLinesResolve() {
        for constellation in ConstellationCatalog.constellations {
            for (a, b) in constellation.lines {
                #expect(StarCatalog.starsByKey[a] != nil,
                        "\(constellation.abbreviation): unresolved star \(a)")
                #expect(StarCatalog.starsByKey[b] != nil,
                        "\(constellation.abbreviation): unresolved star \(b)")
            }
            #expect(ConstellationCatalog.names[constellation.abbreviation] != nil)
        }
    }

    @Test func messierCatalogIsComplete() {
        #expect(MessierCatalog.objects.count == 110)
        let numbers = Set(MessierCatalog.objects.map(\.messierNumber))
        #expect(numbers == Set(1...110))
        for object in MessierCatalog.objects {
            #expect(object.raHours >= 0 && object.raHours < 24)
            #expect(object.decDegrees > -90 && object.decDegrees < 90)
            #expect(ConstellationCatalog.names[object.constellationAbbreviation] != nil,
                    "M\(object.messierNumber): unknown constellation \(object.constellationAbbreviation)")
        }
    }

    @Test func starConstellationsHaveNames() {
        for star in StarCatalog.stars {
            #expect(ConstellationCatalog.names[star.constellationAbbreviation] != nil,
                    "\(star.key): unknown constellation \(star.constellationAbbreviation)")
        }
    }

    @Test func caldwellCatalogIsValid() {
        let objects = CaldwellCatalog.objects
        #expect(objects.count == 109)
        #expect(Set(objects.map(\.catalogNumber)) == Set(1...109))
        for object in objects {
            #expect(object.raHours >= 0 && object.raHours < 24)
            #expect(object.decDegrees > -90 && object.decDegrees < 90)
            #expect(ConstellationCatalog.names[object.constellationAbbreviation] != nil,
                    "C\(object.catalogNumber): unknown constellation \(object.constellationAbbreviation)")
        }
    }

    @Test func ngcHighlightsAreValid() {
        let objects = NGCHighlights.objects
        #expect(objects.count >= 30)
        var seen = Set<Int>()
        for object in objects {
            #expect(!seen.contains(object.catalogNumber), "duplicate NGC \(object.catalogNumber)")
            seen.insert(object.catalogNumber)
            #expect(object.raHours >= 0 && object.raHours < 24)
            #expect(object.decDegrees > -90 && object.decDegrees < 90)
            #expect(ConstellationCatalog.names[object.constellationAbbreviation] != nil,
                    "NGC \(object.catalogNumber): unknown constellation \(object.constellationAbbreviation)")
        }
    }

    @Test func caldwellSearchableByDesignationAndName() {
        let catalog = SkyCatalog()
        #expect(catalog.search("C14").contains { $0.id == "c014" })
        #expect(catalog.search("Double Cluster").contains {
            ($0 as? DeepSkyObject)?.commonName == "Double Cluster"
        })
    }

    @Test func hygLoaderParsesSample() {
        let csv = """
        id,proper,ra,dec,dist,mag,ci,con
        1,Sirius,6.7525,-16.7161,2.64,-1.46,0.00,CMa
        2,,12.0,45.0,100.0,4.2,0.65,UMa
        3,TooFaint,1.0,1.0,10.0,9.9,0.5,Ori
        """
        let stars = HYGCatalogLoader.parse(csv: csv, magnitudeLimit: 6.5)
        #expect(stars.count == 2)
        #expect(stars.first?.properName == "Sirius")
        #expect(abs((stars.first?.distanceLy ?? 0) - 2.64 * 3.26156) < 0.01)
    }
}
