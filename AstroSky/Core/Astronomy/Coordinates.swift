//
//  Coordinates.swift
//  AstroSky
//
//  Celestial coordinate systems and transformations.
//  References: Meeus, "Astronomical Algorithms", 2nd ed., chapters 13, 16, 22.
//

import Foundation
import simd

// MARK: - Coordinate types

/// Equatorial coordinates (right ascension / declination), angles in radians.
struct EquatorialCoordinates: Equatable, Sendable {
    /// Right ascension in radians, [0, 2π).
    var rightAscension: Double
    /// Declination in radians, [-π/2, π/2].
    var declination: Double

    init(rightAscension: Double, declination: Double) {
        self.rightAscension = AstroMath.normalizedRadians(rightAscension)
        self.declination = declination
    }

    init(raHours: Double, decDegrees: Double) {
        self.init(rightAscension: raHours * AstroMath.hoursToRad,
                  declination: decDegrees * AstroMath.degToRad)
    }

    var raHours: Double { rightAscension * AstroMath.radToHours }
    var decDegrees: Double { declination * AstroMath.radToDeg }

    /// Unit vector in the equatorial frame:
    /// +X toward the vernal equinox (RA 0h), +Y toward RA 6h, +Z toward the
    /// north celestial pole.
    var unitVector: SIMD3<Double> {
        let cd = cos(declination)
        return SIMD3(cd * cos(rightAscension), cd * sin(rightAscension), sin(declination))
    }
}

/// Horizontal (alt-azimuth) coordinates, angles in radians.
/// Azimuth is measured from north, increasing eastward.
struct HorizontalCoordinates: Equatable, Sendable {
    var altitude: Double
    var azimuth: Double

    var altitudeDegrees: Double { altitude * AstroMath.radToDeg }
    var azimuthDegrees: Double { AstroMath.normalizedDegrees(azimuth * AstroMath.radToDeg) }

    var isAboveHorizon: Bool { altitude > 0 }

    /// Compass point ("N", "NE", …) for the azimuth.
    var compassDirection: String {
        let points = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                      "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = Int((azimuthDegrees / 22.5).rounded()) % 16
        return points[index]
    }
}

/// Geocentric ecliptic coordinates, angles in radians.
struct EclipticCoordinates: Equatable, Sendable {
    var longitude: Double
    var latitude: Double
}

/// An observer on the Earth's surface. Angles in radians, altitude in meters.
struct Observer: Equatable, Sendable {
    var latitude: Double
    var longitude: Double
    var altitude: Double

    init(latitude: Double, longitude: Double, altitude: Double = 0) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
    }

    init(latitudeDegrees: Double, longitudeDegrees: Double, altitude: Double = 0) {
        self.init(latitude: latitudeDegrees * AstroMath.degToRad,
                  longitude: longitudeDegrees * AstroMath.degToRad,
                  altitude: altitude)
    }

    var latitudeDegrees: Double { latitude * AstroMath.radToDeg }
    var longitudeDegrees: Double { longitude * AstroMath.radToDeg }

    /// Greenwich, a neutral default before location authorization resolves.
    static let `default` = Observer(latitudeDegrees: 51.4779, longitudeDegrees: 0.0)
}

// MARK: - Transformations

enum CoordinateTransforms {
    /// Mean obliquity of the ecliptic in radians (Meeus eq. 22.2, truncated).
    static func meanObliquity(julianDate jd: Double) -> Double {
        let t = AstroTime.julianCenturies(julianDate: jd)
        let seconds = 21.448 - 46.8150 * t - 0.00059 * t * t + 0.001813 * t * t * t
        let degrees = 23.0 + 26.0 / 60.0 + seconds / 3600.0
        return degrees * AstroMath.degToRad
    }

    /// Convert geocentric ecliptic to equatorial coordinates (Meeus eq. 13.3, 13.4).
    static func eclipticToEquatorial(_ ecl: EclipticCoordinates, julianDate jd: Double) -> EquatorialCoordinates {
        let eps = meanObliquity(julianDate: jd)
        let sinEps = sin(eps), cosEps = cos(eps)
        let sinLambda = sin(ecl.longitude), cosLambda = cos(ecl.longitude)
        let sinBeta = sin(ecl.latitude), cosBeta = cos(ecl.latitude)
        let tanBeta = cosBeta == 0 ? .infinity : sinBeta / cosBeta

        let ra = atan2(sinLambda * cosEps - tanBeta * sinEps, cosLambda)
        let dec = asin(sinBeta * cosEps + cosBeta * sinEps * sinLambda)
        return EquatorialCoordinates(rightAscension: ra, declination: dec)
    }

    /// Convert equatorial coordinates to horizontal coordinates for an observer.
    /// Azimuth is measured from north, increasing eastward (Meeus eq. 13.5, 13.6
    /// shifted from the south-based convention).
    static func equatorialToHorizontal(_ eq: EquatorialCoordinates,
                                       localSiderealTime lst: Double,
                                       latitude: Double) -> HorizontalCoordinates {
        let hourAngle = AstroMath.signedRadians(lst - eq.rightAscension)
        let sinLat = sin(latitude), cosLat = cos(latitude)
        let sinDec = sin(eq.declination), cosDec = cos(eq.declination)
        let sinH = sin(hourAngle), cosH = cos(hourAngle)

        let altitude = asin(sinLat * sinDec + cosLat * cosDec * cosH)
        // Azimuth from south, westward positive:
        let azimuthSouth = atan2(sinH, cosH * sinLat - (sinDec / cosDec) * cosLat)
        let azimuth = AstroMath.normalizedRadians(azimuthSouth + .pi)
        return HorizontalCoordinates(altitude: altitude, azimuth: azimuth)
    }

    /// Convenience: equatorial → horizontal for an observer at a given time.
    static func horizontal(of eq: EquatorialCoordinates,
                           julianDate jd: Double,
                           observer: Observer) -> HorizontalCoordinates {
        let lst = AstroTime.localMeanSiderealTime(julianDate: jd, longitude: observer.longitude)
        return equatorialToHorizontal(eq, localSiderealTime: lst, latitude: observer.latitude)
    }

    /// Atmospheric refraction in radians to *add* to a true (airless) altitude,
    /// using Bennett's formula (Meeus eq. 16.4). Valid for altitudes ≥ -1°.
    static func refraction(trueAltitude: Double) -> Double {
        let hDeg = max(trueAltitude * AstroMath.radToDeg, -1.0)
        let argument = (hDeg + 7.31 / (hDeg + 4.4)) * AstroMath.degToRad
        let rArcminutes = 1.02 / tan(argument)
        return rArcminutes / 60.0 * AstroMath.degToRad
    }

    /// Angular separation between two equatorial positions, in radians.
    static func angularSeparation(_ a: EquatorialCoordinates, _ b: EquatorialCoordinates) -> Double {
        let dot = simd_dot(a.unitVector, b.unitVector)
        return acos(min(1.0, max(-1.0, dot)))
    }

    /// Precess J2000.0 equatorial coordinates to the mean equinox of date.
    /// Rigorous rotation using the Meeus ch. 21 angles ζ, z, θ.
    static func precessFromJ2000(_ eq: EquatorialCoordinates, julianDate jd: Double) -> EquatorialCoordinates {
        let v = precessionMatrixFromJ2000(julianDate: jd) * eq.unitVector
        let ra = atan2(v.y, v.x)
        let dec = asin(min(1.0, max(-1.0, v.z)))
        return EquatorialCoordinates(rightAscension: ra, declination: dec)
    }

    /// Rotation matrix taking a J2000.0 equatorial unit vector to the mean
    /// equinox of date: v_date = P · v_J2000 (Meeus ch. 21 angles ζ, z, θ,
    /// composed as R3(-z)·R2(θ)·R3(-ζ)).
    static func precessionMatrixFromJ2000(julianDate jd: Double) -> simd_double3x3 {
        let t = AstroTime.julianCenturies(julianDate: jd)
        let arcsec = AstroMath.degToRad / 3600.0
        let zeta = (2306.2181 * t + 0.30188 * t * t + 0.017998 * t * t * t) * arcsec
        let z = (2306.2181 * t + 1.09468 * t * t + 0.018203 * t * t * t) * arcsec
        let theta = (2004.3109 * t - 0.42665 * t * t - 0.041833 * t * t * t) * arcsec

        let cz = cos(zeta), sz = sin(zeta)
        let ct = cos(theta), st = sin(theta)
        let cZ = cos(z), sZ = sin(z)

        // Rows of the composite rotation (Meeus / Explanatory Supplement).
        let row0 = SIMD3(cz * ct * cZ - sz * sZ, -sz * ct * cZ - cz * sZ, -st * cZ)
        let row1 = SIMD3(cz * ct * sZ + sz * cZ, -sz * ct * sZ + cz * cZ, -st * sZ)
        let row2 = SIMD3(cz * st, -sz * st, ct)
        return simd_double3x3(rows: [row0, row1, row2])
    }
}
