//
//  MinorBodies.swift
//  AstroSky
//
//  Keplerian ephemeris for bright minor planets from osculating elements
//  (J2000 ecliptic). Elements are JPL SBDB values at their stated epoch; the
//  mean anomaly is advanced to the requested date. Accurate to arcminutes for
//  a few years around the epoch — plenty for AR display.
//  Reference: standard two-body propagation; H,G magnitude from Bowell et al.
//

import Foundation
import simd

struct MinorBodyElements: Sendable {
    let key: String
    let name: String
    let a: Double          // semi-major axis, AU
    let e: Double          // eccentricity
    let iDeg: Double       // inclination
    let nodeDeg: Double    // longitude of ascending node Ω
    let argPeriDeg: Double // argument of perihelion ω
    let mDeg: Double       // mean anomaly at epoch
    let epochJD: Double    // osculating epoch (TDB)
    let h: Double          // absolute magnitude H
    let g: Double          // slope parameter G
}

struct MinorBodyState {
    var equatorialJ2000: EquatorialCoordinates
    var distanceAU: Double
    var heliocentricDistanceAU: Double
    var magnitude: Double
}

enum MinorBodyEphemeris {
    /// Bright, easily-seen minor planets (JPL SBDB osculating elements,
    /// epoch JD 2461200.5 TDB = 2026-Aug-13).
    static let bodies: [MinorBodyElements] = [
        MinorBodyElements(key: "ceres", name: "Ceres",
                          a: 2.765552595, e: 0.079692295, iDeg: 10.58802780,
                          nodeDeg: 80.24862682, argPeriDeg: 73.29421453, mDeg: 274.41934638,
                          epochJD: 2_461_200.5, h: 3.34, g: 0.12),
        MinorBodyElements(key: "vesta", name: "Vesta",
                          a: 2.361365965, e: 0.090203744, iDeg: 7.14392555,
                          nodeDeg: 103.70129327, argPeriDeg: 151.46864782, mDeg: 81.19015608,
                          epochJD: 2_461_200.5, h: 3.25, g: 0.32),
        MinorBodyElements(key: "pallas", name: "Pallas",
                          a: 2.769559011, e: 0.230700100, iDeg: 34.93279322,
                          nodeDeg: 172.88661934, argPeriDeg: 310.96991617, mDeg: 254.24965217,
                          epochJD: 2_461_200.5, h: 4.12, g: 0.11),
    ]

    /// Heliocentric rectangular position in the J2000 ecliptic frame (AU).
    static func heliocentricPosition(_ el: MinorBodyElements, julianDate jd: Double) -> SIMD3<Double> {
        // Advance the mean anomaly from the osculating epoch.
        let n = 0.9856076686 / pow(el.a, 1.5)                 // deg/day (Gaussian)
        let meanAnomaly = (el.mDeg + n * (jd - el.epochJD)) * AstroMath.degToRad
        let eAnom = AstroMath.solveKepler(meanAnomaly: AstroMath.normalizedRadians(meanAnomaly),
                                          eccentricity: el.e)

        let xp = el.a * (cos(eAnom) - el.e)
        let yp = el.a * sqrt(1 - el.e * el.e) * sin(eAnom)

        let omega = el.argPeriDeg * AstroMath.degToRad
        let node = el.nodeDeg * AstroMath.degToRad
        let inc = el.iDeg * AstroMath.degToRad
        let cosO = cos(omega), sinO = sin(omega)
        let cosN = cos(node), sinN = sin(node)
        let cosI = cos(inc), sinI = sin(inc)

        let x = (cosO * cosN - sinO * sinN * cosI) * xp + (-sinO * cosN - cosO * sinN * cosI) * yp
        let y = (cosO * sinN + sinO * cosN * cosI) * xp + (-sinO * sinN + cosO * cosN * cosI) * yp
        let z = (sinO * sinI) * xp + (cosO * sinI) * yp
        return SIMD3(x, y, z)
    }

    /// Full geocentric state (J2000 equatorial), with H,G apparent magnitude.
    static func state(_ el: MinorBodyElements, julianDate jd: Double) -> MinorBodyState {
        let helio = heliocentricPosition(el, julianDate: jd)
        let earth = PlanetEphemeris.heliocentricPosition(of: .earth, julianDate: jd)
        let geo = helio - earth

        let distance = simd_length(geo)
        let sunDistance = simd_length(helio)
        let earthSunDistance = simd_length(earth)

        let longitude = AstroMath.normalizedRadians(atan2(geo.y, geo.x))
        let latitude = atan2(geo.z, sqrt(geo.x * geo.x + geo.y * geo.y))
        let ecliptic = EclipticCoordinates(longitude: longitude, latitude: latitude)
        let equatorial = CoordinateTransforms.eclipticToEquatorial(ecliptic, julianDate: AstroTime.j2000)

        // Phase angle (Sun–body–Earth) via the law of cosines.
        let cosPhase = (sunDistance * sunDistance + distance * distance
            - earthSunDistance * earthSunDistance) / (2 * sunDistance * distance)
        let alpha = acos(min(1, max(-1, cosPhase)))

        // Bowell H,G photometric system.
        let tanHalf = tan(alpha / 2)
        let phi1 = exp(-3.33 * pow(tanHalf, 0.63))
        let phi2 = exp(-1.87 * pow(tanHalf, 1.22))
        let magnitude = el.h + 5 * log10(sunDistance * distance)
            - 2.5 * log10((1 - el.g) * phi1 + el.g * phi2)

        return MinorBodyState(equatorialJ2000: equatorial,
                              distanceAU: distance,
                              heliocentricDistanceAU: sunDistance,
                              magnitude: magnitude)
    }
}

/// CelestialObject wrapper for a minor planet.
struct MinorBodyObject: CelestialObject, Identifiable, Sendable {
    let elements: MinorBodyElements

    var id: String { "minor.\(elements.key)" }
    var name: String { elements.name }
    var subtitle: String { "Minor planet · main-belt asteroid" }
    var kind: CelestialObjectKind { .minorBody }
    var magnitude: Double? { MinorBodyEphemeris.state(elements, julianDate: AstroTime.julianDate(Date())).magnitude }

    func skyPosition(julianDate jd: Double, observer: Observer) -> SkyPosition {
        let state = MinorBodyEphemeris.state(elements, julianDate: jd)
        return SkyPosition(equatorialJ2000: state.equatorialJ2000,
                           horizontal: horizontalFromJ2000(state.equatorialJ2000,
                                                           julianDate: jd, observer: observer),
                           distanceDescription: AstroFormat.distanceAU(state.distanceAU))
    }

    func infoRows(julianDate jd: Double, observer: Observer) -> [(label: String, value: String)] {
        let state = MinorBodyEphemeris.state(elements, julianDate: jd)
        return [
            ("Magnitude", AstroFormat.magnitude(state.magnitude)),
            ("Distance from Earth", AstroFormat.distanceAU(state.distanceAU)),
            ("Distance from Sun", AstroFormat.distanceAU(state.heliocentricDistanceAU)),
            ("Absolute magnitude", String(format: "H = %.2f", elements.h)),
            ("Semi-major axis", String(format: "%.3f AU", elements.a)),
        ]
    }

    static let all: [MinorBodyObject] = MinorBodyEphemeris.bodies.map { MinorBodyObject(elements: $0) }
}
