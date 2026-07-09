//
//  Sun.swift
//  AstroSky
//
//  Low-precision solar ephemeris, accurate to ~0.01°.
//  Reference: Meeus, "Astronomical Algorithms", 2nd ed., chapter 25.
//

import Foundation

enum SunEphemeris {
    struct Position {
        /// Geocentric ecliptic coordinates (radians), mean equinox of date.
        var ecliptic: EclipticCoordinates
        /// Equatorial coordinates (radians), mean equinox of date.
        var equatorial: EquatorialCoordinates
        /// Earth–Sun distance in astronomical units.
        var distanceAU: Double
    }

    /// Geocentric solar position for a Julian Date (UT is fine at this precision).
    static func position(julianDate jd: Double) -> Position {
        let t = AstroTime.julianCenturies(julianDate: jd)

        // Geometric mean longitude and mean anomaly (degrees).
        let l0 = 280.46646 + 36000.76983 * t + 0.0003032 * t * t
        let m = 357.52911 + 35999.05029 * t - 0.0001537 * t * t
        let mRad = m * AstroMath.degToRad

        // Eccentricity of Earth's orbit.
        let e = 0.016708634 - 0.000042037 * t - 0.0000001267 * t * t

        // Equation of center (degrees).
        let c = (1.914602 - 0.004817 * t - 0.000014 * t * t) * sin(mRad)
            + (0.019993 - 0.000101 * t) * sin(2 * mRad)
            + 0.000289 * sin(3 * mRad)

        // True longitude and anomaly.
        let trueLongitude = l0 + c
        let trueAnomaly = (m + c) * AstroMath.degToRad

        // Radius vector (AU), Meeus eq. 25.5.
        let distance = 1.000001018 * (1 - e * e) / (1 + e * cos(trueAnomaly))

        let lambda = AstroMath.normalizedDegrees(trueLongitude) * AstroMath.degToRad
        let ecliptic = EclipticCoordinates(longitude: lambda, latitude: 0)

        // Apparent equatorial place: add nutation in longitude and annual
        // aberration (−20.4898″ / R, Meeus ch. 25), then convert with the true
        // obliquity. The `ecliptic` field stays geometric (mean of date).
        let nutation = Nutation.nutation(julianDate: jd)
        let aberration = -20.4898 / distance / 3600.0 * AstroMath.degToRad
        let apparentLambda = lambda + nutation.longitude + aberration
        let apparentEcliptic = EclipticCoordinates(longitude: apparentLambda, latitude: 0)
        let equatorial = CoordinateTransforms.eclipticToEquatorial(
            apparentEcliptic, obliquity: CoordinateTransforms.trueObliquity(julianDate: jd))
        return Position(ecliptic: ecliptic, equatorial: equatorial, distanceAU: distance)
    }
}
