//
//  AstroTime.swift
//  AstroSky
//
//  Julian dates and sidereal time.
//  References: Meeus, "Astronomical Algorithms", 2nd ed., chapters 7 & 12.
//

import Foundation

enum AstroTime {
    /// Julian Date of the Unix epoch (1970-01-01T00:00:00 UTC).
    static let unixEpochJD = 2440587.5

    /// Julian Date of the standard epoch J2000.0 (2000-01-01T12:00:00 TT).
    static let j2000 = 2451545.0

    /// Julian Date (UT) for a given `Date`.
    static func julianDate(_ date: Date) -> Double {
        unixEpochJD + date.timeIntervalSince1970 / 86400.0
    }

    /// `Date` for a given Julian Date (UT).
    static func date(julianDate jd: Double) -> Date {
        Date(timeIntervalSince1970: (jd - unixEpochJD) * 86400.0)
    }

    /// Julian centuries of 36525 days since J2000.0.
    static func julianCenturies(julianDate jd: Double) -> Double {
        (jd - j2000) / 36525.0
    }

    /// Greenwich Mean Sidereal Time in radians, normalized to [0, 2π).
    /// Meeus eq. 12.4.
    static func greenwichMeanSiderealTime(julianDate jd: Double) -> Double {
        let t = julianCenturies(julianDate: jd)
        var thetaDegrees = 280.46061837
            + 360.98564736629 * (jd - j2000)
            + 0.000387933 * t * t
            - t * t * t / 38_710_000.0
        thetaDegrees = AstroMath.normalizedDegrees(thetaDegrees)
        return thetaDegrees * AstroMath.degToRad
    }

    /// Local Mean Sidereal Time in radians for an observer at `longitude`
    /// (radians, positive east), normalized to [0, 2π).
    static func localMeanSiderealTime(julianDate jd: Double, longitude: Double) -> Double {
        AstroMath.normalizedRadians(greenwichMeanSiderealTime(julianDate: jd) + longitude)
    }

    /// Greenwich *Apparent* Sidereal Time in radians: GMST plus the equation of
    /// the equinoxes, Δψ·cos ε (Meeus ch. 12). Use for apparent hour angles.
    static func greenwichApparentSiderealTime(julianDate jd: Double) -> Double {
        let nutation = Nutation.nutation(julianDate: jd)
        let epsilon = CoordinateTransforms.trueObliquity(julianDate: jd)
        return AstroMath.normalizedRadians(
            greenwichMeanSiderealTime(julianDate: jd) + nutation.longitude * cos(epsilon))
    }

    /// Local Apparent Sidereal Time in radians for an observer at `longitude`.
    static func localApparentSiderealTime(julianDate jd: Double, longitude: Double) -> Double {
        AstroMath.normalizedRadians(greenwichApparentSiderealTime(julianDate: jd) + longitude)
    }

}
