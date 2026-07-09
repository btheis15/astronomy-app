//
//  Satellite.swift
//  AstroSky
//
//  An Earth-orbiting satellite observable from the ground: SGP4 state
//  converted to topocentric look angles, sunlit/eclipse test and pass
//  prediction support.
//

import Foundation
import simd

struct SatelliteObservation {
    var horizontal: HorizontalCoordinates
    /// Range from observer in kilometers.
    var rangeKm: Double
    /// Geodetic altitude of the satellite in kilometers.
    var altitudeKm: Double
    /// True when the satellite is illuminated by the Sun (not in Earth's shadow).
    var isSunlit: Bool
    /// Speed relative to the ECI frame in km/s.
    var speedKmPerSec: Double
}

struct SatellitePass: Identifiable, Sendable {
    var satelliteID: String
    var satelliteName: String
    var start: Date
    var peak: Date
    var end: Date
    /// Maximum altitude reached, radians.
    var maxAltitude: Double
    /// True if the satellite is sunlit at peak while the sky is dark —
    /// i.e. actually visible to the naked eye.
    var isVisible: Bool

    var id: String { "\(satelliteID)-\(Int(start.timeIntervalSince1970))" }
}

final class Satellite: CelestialObject, Identifiable, @unchecked Sendable {
    let tle: TLE
    /// Celestrak group this came from ("stations", "visual", "starlink").
    let group: String
    private let propagator: SGP4

    init?(tle: TLE, group: String) {
        guard let propagator = try? SGP4(tle: tle) else { return nil }
        self.tle = tle
        self.group = group
        self.propagator = propagator
    }

    var isStarlink: Bool { tle.name.uppercased().contains("STARLINK") }
    var isISS: Bool { tle.catalogNumber == 25544 }

    // MARK: CelestialObject

    var id: String { "sat.\(tle.catalogNumber)" }
    var name: String { displayName(tle.name) }

    var subtitle: String {
        if isISS { return "International Space Station" }
        if isStarlink { return "Starlink constellation satellite" }
        return "Satellite · NORAD \(tle.catalogNumber)"
    }

    var kind: CelestialObjectKind { .satellite }
    var magnitude: Double? { nil }

    func skyPosition(julianDate jd: Double, observer: Observer) -> SkyPosition {
        let obs = observe(julianDate: jd, observer: observer)
        // Satellites are not on the celestial sphere; report the equatorial
        // direction implied by the topocentric line of sight (of-date frame
        // treated as J2000 — the arcminutes-level difference is irrelevant
        // for a fast-moving satellite).
        let eq = Self.equatorialDirection(of: obs?.horizontal ?? HorizontalCoordinates(altitude: 0, azimuth: 0),
                                          julianDate: jd, observer: observer)
        return SkyPosition(equatorialJ2000: eq,
                           horizontal: obs?.horizontal ?? HorizontalCoordinates(altitude: -.pi / 2, azimuth: 0),
                           distanceDescription: obs.map { String(format: "%.0f km", $0.rangeKm) })
    }

    func infoRows(julianDate jd: Double, observer: Observer) -> [(label: String, value: String)] {
        var rows: [(String, String)] = [
            ("NORAD ID", "\(tle.catalogNumber)"),
            ("Orbital period", String(format: "%.1f min", tle.periodMinutes)),
            ("Inclination", String(format: "%.1f°", tle.inclination * AstroMath.radToDeg)),
        ]
        if let obs = observe(julianDate: jd, observer: observer) {
            rows.append(("Range", String(format: "%.0f km", obs.rangeKm)))
            rows.append(("Orbit altitude", String(format: "%.0f km", obs.altitudeKm)))
            rows.append(("Speed", String(format: "%.2f km/s", obs.speedKmPerSec)))
            rows.append(("Illumination", obs.isSunlit ? "Sunlit" : "In Earth's shadow"))
        }
        return rows
    }

    // MARK: Topocentric observation

    /// Full observation (look angles, range, sunlit state); nil if the
    /// propagation failed (e.g. decayed orbit).
    func observe(julianDate jd: Double, observer: Observer) -> SatelliteObservation? {
        guard let state = try? propagator.propagate(julianDate: jd) else { return nil }

        let gmst = AstroTime.greenwichMeanSiderealTime(julianDate: jd)

        // TEME → ECEF (rotate about Earth's axis by GMST).
        let cosG = cos(gmst), sinG = sin(gmst)
        let ecef = SIMD3(cosG * state.position.x + sinG * state.position.y,
                         -sinG * state.position.x + cosG * state.position.y,
                         state.position.z)

        let observerECEF = Self.geodeticToECEF(observer)
        let rangeVector = ecef - observerECEF

        // ECEF → ENU at the observer.
        let sinLat = sin(observer.latitude), cosLat = cos(observer.latitude)
        let sinLon = sin(observer.longitude), cosLon = cos(observer.longitude)
        let east = -sinLon * rangeVector.x + cosLon * rangeVector.y
        let north = -sinLat * cosLon * rangeVector.x - sinLat * sinLon * rangeVector.y + cosLat * rangeVector.z
        let up = cosLat * cosLon * rangeVector.x + cosLat * sinLon * rangeVector.y + sinLat * rangeVector.z

        let range = simd_length(rangeVector)
        let altitude = asin(up / range)
        let azimuth = AstroMath.normalizedRadians(atan2(east, north))

        let geocentricRadius = simd_length(state.position)
        let satelliteAltKm = geocentricRadius - 6371.0

        return SatelliteObservation(
            horizontal: HorizontalCoordinates(altitude: altitude, azimuth: azimuth),
            rangeKm: range,
            altitudeKm: satelliteAltKm,
            isSunlit: Self.isSunlit(temePosition: state.position, julianDate: jd),
            speedKmPerSec: simd_length(state.velocity))
    }

    /// Predict passes above `minimumAltitude` within the next `hours` hours.
    func passes(observer: Observer,
                startingAt start: Date,
                hours: Double = 24,
                minimumAltitude: Double = 10.0 * AstroMath.degToRad) -> [SatellitePass] {
        var result: [SatellitePass] = []
        let step: TimeInterval = 30
        let end = start.addingTimeInterval(hours * 3600)

        var current = start
        var inPass = false
        var passStart = start
        var peakDate = start
        var peakAltitude = -Double.pi

        func altitude(at date: Date) -> Double {
            observe(julianDate: AstroTime.julianDate(date), observer: observer)?
                .horizontal.altitude ?? -.pi / 2
        }

        while current <= end {
            let alt = altitude(at: current)
            if alt > minimumAltitude {
                if !inPass {
                    inPass = true
                    passStart = current
                    peakAltitude = alt
                    peakDate = current
                } else if alt > peakAltitude {
                    peakAltitude = alt
                    peakDate = current
                }
            } else if inPass {
                inPass = false
                result.append(makePass(observer: observer, start: passStart,
                                       peak: peakDate, end: current, maxAltitude: peakAltitude))
            }
            current = current.addingTimeInterval(step)
        }
        if inPass {
            result.append(makePass(observer: observer, start: passStart,
                                   peak: peakDate, end: end, maxAltitude: peakAltitude))
        }
        return result
    }

    private func makePass(observer: Observer, start: Date, peak: Date,
                          end: Date, maxAltitude: Double) -> SatellitePass {
        let peakJD = AstroTime.julianDate(peak)
        let sunEq = SunEphemeris.position(julianDate: peakJD).equatorial
        let sunAltitude = CoordinateTransforms.horizontal(of: sunEq, julianDate: peakJD,
                                                          observer: observer).altitude
        let sunlit = observe(julianDate: peakJD, observer: observer)?.isSunlit ?? false
        let darkSky = sunAltitude < -6.0 * AstroMath.degToRad
        return SatellitePass(satelliteID: id,
                             satelliteName: name,
                             start: start,
                             peak: peak,
                             end: end,
                             maxAltitude: maxAltitude,
                             isVisible: sunlit && darkSky)
    }

    // MARK: Static helpers

    /// WGS-84 geodetic coordinates → ECEF (km).
    static func geodeticToECEF(_ observer: Observer) -> SIMD3<Double> {
        let a = 6378.137                      // WGS-84 semi-major axis, km
        let f = 1.0 / 298.257223563
        let e2 = f * (2 - f)
        let sinLat = sin(observer.latitude), cosLat = cos(observer.latitude)
        let n = a / (1 - e2 * sinLat * sinLat).squareRoot()
        let h = observer.altitude / 1000.0    // meters → km
        return SIMD3((n + h) * cosLat * cos(observer.longitude),
                     (n + h) * cosLat * sin(observer.longitude),
                     (n * (1 - e2) + h) * sinLat)
    }

    /// Cylindrical Earth-shadow test in the TEME/ECI frame.
    static func isSunlit(temePosition: SIMD3<Double>, julianDate jd: Double) -> Bool {
        let sun = SunEphemeris.position(julianDate: jd)
        // Unit vector to the Sun in equatorial (≈ TEME) coordinates.
        let sunDir = sun.equatorial.unitVector
        let projection = simd_dot(temePosition, sunDir)
        if projection >= 0 { return true }    // on the sunny side
        let perpendicular = temePosition - projection * sunDir
        return simd_length(perpendicular) > 6371.0
    }

    /// Equatorial direction (of date) corresponding to a topocentric
    /// alt/az line of sight.
    static func equatorialDirection(of horizontal: HorizontalCoordinates,
                                    julianDate jd: Double,
                                    observer: Observer) -> EquatorialCoordinates {
        let lst = AstroTime.localMeanSiderealTime(julianDate: jd, longitude: observer.longitude)
        let sinAlt = sin(horizontal.altitude), cosAlt = cos(horizontal.altitude)
        let sinAz = sin(horizontal.azimuth), cosAz = cos(horizontal.azimuth)
        let sinLat = sin(observer.latitude), cosLat = cos(observer.latitude)

        let declination = asin(sinLat * sinAlt + cosLat * cosAlt * cosAz)
        // Hour angle from the same spherical triangle.
        let hourAngle = atan2(-sinAz * cosAlt, sinAlt * cosLat - cosAlt * cosAz * sinLat)
        let ra = AstroMath.normalizedRadians(lst - hourAngle)
        return EquatorialCoordinates(rightAscension: ra, declination: declination)
    }

    private func displayName(_ raw: String) -> String {
        var name = raw
        // "ISS (ZARYA)" → "ISS", "STARLINK-3042" → "Starlink-3042"
        if isISS { return "ISS" }
        if let parenIndex = name.firstIndex(of: "(") {
            name = String(name[..<parenIndex]).trimmingCharacters(in: .whitespaces)
        }
        if isStarlink {
            return name.capitalized
        }
        return name
    }
}
