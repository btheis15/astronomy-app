//
//  Moon.swift
//  AstroSky
//
//  Lunar ephemeris from a truncated ELP-2000/82 series, accurate to a few
//  arcminutes in longitude — far better than needed for AR display.
//  Reference: Meeus, "Astronomical Algorithms", 2nd ed., chapter 47.
//

import Foundation

enum MoonEphemeris {
    struct Position {
        /// Geocentric ecliptic coordinates (radians), mean equinox of date.
        var ecliptic: EclipticCoordinates
        /// Equatorial coordinates (radians), mean equinox of date.
        var equatorial: EquatorialCoordinates
        /// Earth–Moon distance in kilometers.
        var distanceKm: Double
    }

    struct PhaseInfo {
        /// Phase angle ψ (Sun–Moon elongation) in radians, [0, π].
        var elongation: Double
        /// Illuminated fraction of the disk, 0…1.
        var illuminatedFraction: Double
        /// Moon age as a fraction of the synodic cycle, 0…1
        /// (0 = new, 0.5 = full).
        var cycleFraction: Double
        var phaseName: String
        /// True when the illuminated limb is growing night over night.
        var isWaxing: Bool
    }

    // Periodic term: coefficient plus multiples of D, M, M', F.
    private struct Term {
        let d: Double, m: Double, mp: Double, f: Double
        let coefficient: Double
        init(_ d: Double, _ m: Double, _ mp: Double, _ f: Double, _ c: Double) {
            self.d = d; self.m = m; self.mp = mp; self.f = f; self.coefficient = c
        }
    }

    // Longitude terms, unit 1e-6 degrees (Meeus table 47.A, leading terms).
    private static let longitudeTerms: [Term] = [
        Term(0, 0, 1, 0, 6_288_774), Term(2, 0, -1, 0, 1_274_027), Term(2, 0, 0, 0, 658_314),
        Term(0, 0, 2, 0, 213_618), Term(0, 1, 0, 0, -185_116), Term(0, 0, 0, 2, -114_332),
        Term(2, 0, -2, 0, 58_793), Term(2, -1, -1, 0, 57_066), Term(2, 0, 1, 0, 53_322),
        Term(2, -1, 0, 0, 45_758), Term(0, 1, -1, 0, -40_923), Term(1, 0, 0, 0, -34_720),
        Term(0, 1, 1, 0, -30_383), Term(2, 0, 0, -2, 15_327), Term(0, 0, 1, 2, -12_528),
        Term(0, 0, 1, -2, 10_980), Term(4, 0, -1, 0, 10_675), Term(0, 0, 3, 0, 10_034),
        Term(4, 0, -2, 0, 8_548), Term(2, 1, -1, 0, -7_888), Term(2, 1, 0, 0, -6_766),
        Term(1, 0, -1, 0, -5_163), Term(1, 1, 0, 0, 4_987), Term(2, -1, 1, 0, 4_036),
        Term(2, 0, 2, 0, 3_994), Term(4, 0, 0, 0, 3_861), Term(2, 0, -3, 0, 3_665),
        Term(0, 1, -2, 0, -2_689), Term(2, 0, -1, 2, -2_602), Term(2, -1, -2, 0, 2_390),
    ]

    // Distance terms, unit 1e-3 km (Meeus table 47.A, leading terms).
    private static let distanceTerms: [Term] = [
        Term(0, 0, 1, 0, -20_905_355), Term(2, 0, -1, 0, -3_699_111), Term(2, 0, 0, 0, -2_955_968),
        Term(0, 0, 2, 0, -569_925), Term(0, 1, 0, 0, 48_888), Term(0, 0, 0, 2, -3_149),
        Term(2, 0, -2, 0, 246_158), Term(2, -1, -1, 0, -152_138), Term(2, 0, 1, 0, -170_733),
        Term(2, -1, 0, 0, -204_586), Term(0, 1, -1, 0, -129_620), Term(1, 0, 0, 0, 108_743),
        Term(0, 1, 1, 0, 104_755), Term(2, 0, 0, -2, 10_321), Term(0, 0, 1, -2, 79_661),
        Term(4, 0, -1, 0, -34_782), Term(0, 0, 3, 0, -23_210), Term(4, 0, -2, 0, -21_636),
        Term(2, 1, -1, 0, 24_208), Term(2, 1, 0, 0, 30_824), Term(1, 0, -1, 0, -8_379),
        Term(1, 1, 0, 0, -16_675), Term(2, -1, 1, 0, -12_831), Term(2, 0, 2, 0, -10_445),
        Term(4, 0, 0, 0, -11_650), Term(2, 0, -3, 0, 14_403),
    ]

    // Latitude terms, unit 1e-6 degrees (Meeus table 47.B, leading terms).
    private static let latitudeTerms: [Term] = [
        Term(0, 0, 0, 1, 5_128_122), Term(0, 0, 1, 1, 280_602), Term(0, 0, 1, -1, 277_693),
        Term(2, 0, 0, -1, 173_237), Term(2, 0, -1, 1, 55_413), Term(2, 0, -1, -1, 46_271),
        Term(2, 0, 0, 1, 32_573), Term(0, 0, 2, 1, 17_198), Term(2, 0, 1, -1, 9_266),
        Term(0, 0, 2, -1, 8_822), Term(2, -1, 0, -1, 8_216), Term(2, 0, -2, -1, 4_324),
        Term(2, 0, 1, 1, 4_200), Term(2, 1, 0, -1, -3_359), Term(2, -1, -1, 1, 2_463),
        Term(2, -1, 0, 1, 2_211), Term(2, -1, -1, -1, 2_065), Term(0, 1, -1, -1, -1_870),
        Term(4, 0, -1, -1, 1_828), Term(0, 1, 0, 1, -1_794),
    ]

    /// Geocentric lunar position for a Julian Date.
    static func position(julianDate jd: Double) -> Position {
        let t = AstroTime.julianCenturies(julianDate: jd)

        // Fundamental arguments (degrees), Meeus eq. 47.1–47.5.
        let lp = 218.3164477 + 481_267.88123421 * t - 0.0015786 * t * t
            + t * t * t / 538_841.0 - t * t * t * t / 65_194_000.0
        let d = 297.8501921 + 445_267.1114034 * t - 0.0018819 * t * t
            + t * t * t / 545_868.0 - t * t * t * t / 113_065_000.0
        let m = 357.5291092 + 35_999.0502909 * t - 0.0001536 * t * t
            + t * t * t / 24_490_000.0
        let mp = 134.9633964 + 477_198.8675055 * t + 0.0087414 * t * t
            + t * t * t / 69_699.0 - t * t * t * t / 14_712_000.0
        let f = 93.2720950 + 483_202.0175233 * t - 0.0036539 * t * t
            - t * t * t / 3_526_000.0 + t * t * t * t / 863_310_000.0

        // Eccentricity correction factor for terms containing M.
        let e = 1.0 - 0.002516 * t - 0.0000074 * t * t

        let dRad = d * AstroMath.degToRad
        let mRad = m * AstroMath.degToRad
        let mpRad = mp * AstroMath.degToRad
        let fRad = f * AstroMath.degToRad

        func eFactor(_ mMultiple: Double) -> Double {
            switch abs(mMultiple) {
            case 1: return e
            case 2: return e * e
            default: return 1.0
            }
        }

        var sumL = 0.0, sumR = 0.0, sumB = 0.0
        for term in longitudeTerms {
            let arg = term.d * dRad + term.m * mRad + term.mp * mpRad + term.f * fRad
            sumL += term.coefficient * eFactor(term.m) * sin(arg)
        }
        for term in distanceTerms {
            let arg = term.d * dRad + term.m * mRad + term.mp * mpRad + term.f * fRad
            sumR += term.coefficient * eFactor(term.m) * cos(arg)
        }
        for term in latitudeTerms {
            let arg = term.d * dRad + term.m * mRad + term.mp * mpRad + term.f * fRad
            sumB += term.coefficient * eFactor(term.m) * sin(arg)
        }

        // Additive corrections (Venus, Jupiter, flattening terms).
        let a1 = (119.75 + 131.849 * t) * AstroMath.degToRad
        let a2 = (53.09 + 479_264.290 * t) * AstroMath.degToRad
        let a3 = (313.45 + 481_266.484 * t) * AstroMath.degToRad
        let lpRad = lp * AstroMath.degToRad
        sumL += 3958 * sin(a1) + 1962 * sin(lpRad - fRad) + 318 * sin(a2)
        sumB += -2235 * sin(lpRad) + 382 * sin(a3) + 175 * sin(a1 - fRad)
            + 175 * sin(a1 + fRad) + 127 * sin(lpRad - mpRad) - 115 * sin(lpRad + mpRad)

        let longitude = AstroMath.normalizedDegrees(lp + sumL / 1_000_000.0) * AstroMath.degToRad
        let latitude = (sumB / 1_000_000.0) * AstroMath.degToRad
        let distance = 385_000.56 + sumR / 1000.0

        let ecliptic = EclipticCoordinates(longitude: longitude, latitude: latitude)
        let equatorial = CoordinateTransforms.eclipticToEquatorial(ecliptic, julianDate: jd)
        return Position(ecliptic: ecliptic, equatorial: equatorial, distanceKm: distance)
    }

    /// Mean length of the synodic month in days.
    static let synodicMonth = 29.530588853

    /// Phase information (illumination, name, waxing/waning) for a Julian Date.
    static func phase(julianDate jd: Double) -> PhaseInfo {
        let moon = position(julianDate: jd)
        let sun = SunEphemeris.position(julianDate: jd)

        // Signed elongation of the Moon east of the Sun along the ecliptic.
        let signedElongation = AstroMath.normalizedRadians(moon.ecliptic.longitude - sun.ecliptic.longitude)
        let cycleFraction = signedElongation / AstroMath.twoPi

        // Geocentric elongation including lunar latitude.
        let cosElong = cos(moon.ecliptic.latitude) * cos(moon.ecliptic.longitude - sun.ecliptic.longitude)
        let elongation = acos(min(1.0, max(-1.0, cosElong)))
        let illuminated = (1.0 - cos(elongation)) / 2.0

        let isWaxing = cycleFraction < 0.5
        let name: String
        switch cycleFraction {
        case ..<0.017, 0.983...: name = "New Moon"
        case ..<0.233: name = "Waxing Crescent"
        case ..<0.267: name = "First Quarter"
        case ..<0.483: name = "Waxing Gibbous"
        case ..<0.517: name = "Full Moon"
        case ..<0.733: name = "Waning Gibbous"
        case ..<0.767: name = "Last Quarter"
        default: name = "Waning Crescent"
        }

        return PhaseInfo(elongation: elongation,
                         illuminatedFraction: illuminated,
                         cycleFraction: cycleFraction,
                         phaseName: name,
                         isWaxing: isWaxing)
    }

    /// Apparent angular diameter of the Moon in radians for a given distance
    /// (lunar radius 1737.4 km).
    static func angularDiameter(distanceKm: Double) -> Double {
        2.0 * atan(1737.4 / distanceKm)
    }
}
