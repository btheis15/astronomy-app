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

    /// Approximate ΔT = TT − UT in seconds (Espenak & Meeus polynomial,
    /// adequate for 2005–2050). Used where dynamical time matters; for the
    /// visual purposes of this app the ~1 arcsecond effect is negligible,
    /// but it keeps the ephemeris honest.
    static func deltaT(julianDate jd: Double) -> Double {
        let year = 2000.0 + (jd - j2000) / 365.25
        let t = year - 2000.0
        return 62.92 + 0.32217 * t + 0.005589 * t * t
    }

    /// Julian Ephemeris Date (TT) for a given UT Julian Date.
    static func julianEphemerisDate(julianDate jd: Double) -> Double {
        jd + deltaT(julianDate: jd) / 86400.0
    }
}
