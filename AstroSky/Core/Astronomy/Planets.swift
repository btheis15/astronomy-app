//
//  Planets.swift
//  AstroSky
//
//  Planetary positions from JPL's Keplerian elements approximation
//  (valid 1800–2050, accuracy of order arcminutes — excellent for AR).
//  Reference: E.M. Standish, "Keplerian Elements for Approximate Positions
//  of the Major Planets", JPL/Caltech; magnitudes from Meeus ch. 41.
//
//  All positions are computed in the J2000.0 ecliptic/equinox frame.
//

import Foundation
import simd

enum Planet: String, CaseIterable, Identifiable, Sendable {
    case mercury, venus, earth, mars, jupiter, saturn, uranus, neptune

    var id: String { rawValue }
    var name: String { rawValue.capitalized }

    /// Planets shown in the sky (everything except Earth).
    static let visible: [Planet] = [.mercury, .venus, .mars, .jupiter, .saturn, .uranus, .neptune]

    var symbol: String {
        switch self {
        case .mercury: "☿"
        case .venus: "♀"
        case .earth: "⊕"
        case .mars: "♂"
        case .jupiter: "♃"
        case .saturn: "♄"
        case .uranus: "♅"
        case .neptune: "♆"
        }
    }

    /// Mean semi-major axis in AU (J2000 value from JPL Keplerian elements).
    var semiMajorAxisAU: Double { PlanetEphemeris.semiMajorAxisAU(self) }

    /// Mean equatorial radius in kilometers.
    var radiusKm: Double {
        switch self {
        case .mercury: 2439.7
        case .venus: 6051.8
        case .earth: 6378.1
        case .mars: 3396.2
        case .jupiter: 71_492
        case .saturn: 60_268
        case .uranus: 25_559
        case .neptune: 24_764
        }
    }
}

struct PlanetPosition {
    var planet: Planet
    /// Geocentric equatorial coordinates, J2000.0 frame.
    var equatorialJ2000: EquatorialCoordinates
    /// Geocentric ecliptic coordinates, J2000.0 frame.
    var eclipticJ2000: EclipticCoordinates
    /// Distance from Earth in AU.
    var distanceAU: Double
    /// Distance from the Sun in AU.
    var heliocentricDistanceAU: Double
    /// Sun–planet–Earth phase angle in radians.
    var phaseAngle: Double
    /// Approximate apparent visual magnitude.
    var magnitude: Double
    /// Apparent angular diameter in radians.
    var angularDiameter: Double
}

enum PlanetEphemeris {
    /// Keplerian elements at J2000 plus per-century rates
    /// (a in AU, angles in degrees). For "earth" these are the Earth–Moon
    /// barycenter elements; the ~4700 km offset to the Earth's center is
    /// negligible at this app's accuracy.
    private struct Elements {
        let a: Double, aDot: Double
        let e: Double, eDot: Double
        let i: Double, iDot: Double
        let l: Double, lDot: Double          // mean longitude
        let peri: Double, periDot: Double    // longitude of perihelion ϖ
        let node: Double, nodeDot: Double    // longitude of ascending node Ω
    }

    private static let elements: [Planet: Elements] = [
        .mercury: Elements(a: 0.38709927, aDot: 0.00000037,
                           e: 0.20563593, eDot: 0.00001906,
                           i: 7.00497902, iDot: -0.00594749,
                           l: 252.25032350, lDot: 149472.67411175,
                           peri: 77.45779628, periDot: 0.16047689,
                           node: 48.33076593, nodeDot: -0.12534081),
        .venus: Elements(a: 0.72333566, aDot: 0.00000390,
                         e: 0.00677672, eDot: -0.00004107,
                         i: 3.39467605, iDot: -0.00078890,
                         l: 181.97909950, lDot: 58517.81538729,
                         peri: 131.60246718, periDot: 0.00268329,
                         node: 76.67984255, nodeDot: -0.27769418),
        .earth: Elements(a: 1.00000261, aDot: 0.00000562,
                         e: 0.01671123, eDot: -0.00004392,
                         i: -0.00001531, iDot: -0.01294668,
                         l: 100.46457166, lDot: 35999.37244981,
                         peri: 102.93768193, periDot: 0.32327364,
                         node: 0.0, nodeDot: 0.0),
        .mars: Elements(a: 1.52371034, aDot: 0.00001847,
                        e: 0.09339410, eDot: 0.00007882,
                        i: 1.84969142, iDot: -0.00813131,
                        l: -4.55343205, lDot: 19140.30268499,
                        peri: -23.94362959, periDot: 0.44441088,
                        node: 49.55953891, nodeDot: -0.29257343),
        .jupiter: Elements(a: 5.20288700, aDot: -0.00011607,
                           e: 0.04838624, eDot: -0.00013253,
                           i: 1.30439695, iDot: -0.00183714,
                           l: 34.39644051, lDot: 3034.74612775,
                           peri: 14.72847983, periDot: 0.21252668,
                           node: 100.47390909, nodeDot: 0.20469106),
        .saturn: Elements(a: 9.53667594, aDot: -0.00125060,
                          e: 0.05386179, eDot: -0.00050991,
                          i: 2.48599187, iDot: 0.00193609,
                          l: 49.95424423, lDot: 1222.49362201,
                          peri: 92.59887831, periDot: -0.41897216,
                          node: 113.66242448, nodeDot: -0.28867794),
        .uranus: Elements(a: 19.18916464, aDot: -0.00196176,
                          e: 0.04725744, eDot: -0.00004397,
                          i: 0.77263783, iDot: -0.00242939,
                          l: 313.23810451, lDot: 428.48202785,
                          peri: 170.95427630, periDot: 0.40805281,
                          node: 74.01692503, nodeDot: 0.04240589),
        .neptune: Elements(a: 30.06992276, aDot: 0.00026291,
                           e: 0.00859048, eDot: 0.00005105,
                           i: 1.77004347, iDot: 0.00035372,
                           l: -55.12002969, lDot: 218.45945325,
                           peri: 44.96476227, periDot: -0.32241464,
                           node: 131.78422574, nodeDot: -0.00508664),
    ]

    /// J2000 semi-major axis in AU, sourced from the Keplerian elements table.
    static func semiMajorAxisAU(_ planet: Planet) -> Double {
        elements[planet]?.a ?? 1.0
    }

    /// Heliocentric rectangular coordinates in the J2000 ecliptic frame (AU).
    static func heliocentricPosition(of planet: Planet, julianDate jd: Double) -> SIMD3<Double> {
        guard let el = elements[planet] else { return .zero }
        let t = AstroTime.julianCenturies(julianDate: jd)

        let a = el.a + el.aDot * t
        let e = el.e + el.eDot * t
        let i = (el.i + el.iDot * t) * AstroMath.degToRad
        let l = el.l + el.lDot * t
        let peri = el.peri + el.periDot * t
        let node = el.node + el.nodeDot * t

        let meanAnomaly = (l - peri) * AstroMath.degToRad
        let omega = (peri - node) * AstroMath.degToRad   // argument of perihelion
        let bigOmega = node * AstroMath.degToRad

        let eAnom = AstroMath.solveKepler(meanAnomaly: meanAnomaly, eccentricity: e)

        // Position in the orbital plane, x' toward perihelion.
        let xp = a * (cos(eAnom) - e)
        let yp = a * sqrt(1 - e * e) * sin(eAnom)

        // Rotate into the J2000 ecliptic frame.
        let cosO = cos(omega), sinO = sin(omega)
        let cosN = cos(bigOmega), sinN = sin(bigOmega)
        let cosI = cos(i), sinI = sin(i)

        let x = (cosO * cosN - sinO * sinN * cosI) * xp + (-sinO * cosN - cosO * sinN * cosI) * yp
        let y = (cosO * sinN + sinO * cosN * cosI) * xp + (-sinO * sinN + cosO * cosN * cosI) * yp
        let z = (sinO * sinI) * xp + (cosO * sinI) * yp
        return SIMD3(x, y, z)
    }

    /// Full geocentric apparent state of a planet, including light-time,
    /// annual aberration and nutation.
    static func position(of planet: Planet, julianDate jd: Double) -> PlanetPosition {
        let earth = heliocentricPosition(of: .earth, julianDate: jd)

        // Light-time correction: the planet is seen where it was τ days ago
        // (τ ≈ 0.0057755 days per AU of range). Two iterations converge amply.
        var lightDays = 0.0
        var helio = heliocentricPosition(of: planet, julianDate: jd)
        var geo = helio - earth
        for _ in 0..<2 {
            lightDays = simd_length(geo) * 0.005_775_518_3
            helio = heliocentricPosition(of: planet, julianDate: jd - lightDays)
            geo = helio - earth
        }

        let distance = simd_length(geo)
        let sunDistance = simd_length(helio)
        let earthSunDistance = simd_length(earth)

        let longitude0 = AstroMath.normalizedRadians(atan2(geo.y, geo.x))
        let latitude0 = atan2(geo.z, sqrt(geo.x * geo.x + geo.y * geo.y))

        // Apparent ecliptic place: annual aberration (Meeus eq. 23.2, using the
        // Sun's longitude and Earth's orbit) plus nutation in longitude.
        let t = AstroTime.julianCenturies(julianDate: jd)
        let kappa = 20.49552 / 3600.0 * AstroMath.degToRad
        let eEarth = 0.016708634 - 0.000042037 * t - 0.0000001267 * t * t
        let periEarth = (102.93735 + 1.71946 * t + 0.00046 * t * t) * AstroMath.degToRad
        let sunLongitude = SunEphemeris.position(julianDate: jd).ecliptic.longitude
        let cosBeta = cos(latitude0)
        let dLon = (-kappa * cos(sunLongitude - longitude0)
                    + eEarth * kappa * cos(periEarth - longitude0)) / (cosBeta == 0 ? 1 : cosBeta)
        let dLat = -kappa * sin(latitude0)
            * (sin(sunLongitude - longitude0) - eEarth * sin(periEarth - longitude0))
        let nutationLon = Nutation.nutation(julianDate: jd).longitude

        let ecliptic = EclipticCoordinates(
            longitude: AstroMath.normalizedRadians(longitude0 + dLon + nutationLon),
            latitude: latitude0 + dLat)

        // J2000 ecliptic → J2000 equatorial (use the J2000 obliquity); callers
        // precess this to the date for display.
        let equatorial = CoordinateTransforms.eclipticToEquatorial(ecliptic, julianDate: AstroTime.j2000)

        // Phase angle from the triangle Sun–planet–Earth (law of cosines).
        let cosPhase = (sunDistance * sunDistance + distance * distance
            - earthSunDistance * earthSunDistance) / (2 * sunDistance * distance)
        let phaseAngle = acos(min(1.0, max(-1.0, cosPhase)))

        let magnitude = apparentMagnitude(of: planet,
                                          heliocentricDistance: sunDistance,
                                          geocentricDistance: distance,
                                          phaseAngle: phaseAngle)
        let angularDiameter = 2.0 * atan(planet.radiusKm / (distance * AstroMath.auKilometers))

        return PlanetPosition(planet: planet,
                              equatorialJ2000: equatorial,
                              eclipticJ2000: ecliptic,
                              distanceAU: distance,
                              heliocentricDistanceAU: sunDistance,
                              phaseAngle: phaseAngle,
                              magnitude: magnitude,
                              angularDiameter: angularDiameter)
    }

    /// Apparent visual magnitude (Meeus ch. 41 / Astronomical Almanac fits).
    /// Saturn's value ignores the ring contribution (up to ~1 mag brighter).
    static func apparentMagnitude(of planet: Planet,
                                  heliocentricDistance r: Double,
                                  geocentricDistance delta: Double,
                                  phaseAngle: Double) -> Double {
        let alpha = phaseAngle * AstroMath.radToDeg
        let base = 5.0 * log10(r * delta)
        switch planet {
        case .mercury:
            return -0.42 + base + 0.0380 * alpha - 0.000273 * alpha * alpha + 0.000002 * alpha * alpha * alpha
        case .venus:
            return -4.40 + base + 0.0009 * alpha + 0.000239 * alpha * alpha - 0.00000065 * alpha * alpha * alpha
        case .earth:
            return 0
        case .mars:
            return -1.52 + base + 0.016 * alpha
        case .jupiter:
            return -9.40 + base + 0.005 * alpha
        case .saturn:
            return -8.88 + base + 0.044 * alpha
        case .uranus:
            return -7.19 + base + 0.002 * alpha
        case .neptune:
            return -6.87 + base
        }
    }
}
