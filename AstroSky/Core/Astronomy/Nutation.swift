//
//  Nutation.swift
//  AstroSky
//
//  Nutation in longitude (Δψ) and obliquity (Δε) from the 1980 IAU theory,
//  truncated to the 13 largest terms of Meeus' Table 22.A. Accurate to about
//  0.5″ — ample for apparent-place corrections at this app's precision.
//  Reference: Meeus, "Astronomical Algorithms", 2nd ed., chapter 22.
//

import Foundation

enum Nutation {
    /// Δψ (nutation in longitude) and Δε (nutation in obliquity), radians.
    struct Result: Sendable {
        var longitude: Double
        var obliquity: Double
    }

    // Each term: integer multiples of the fundamental arguments D, M, M', F, Ω,
    // then the Δψ coefficient (constant + T term) and the Δε coefficient
    // (constant + T term), all in units of 0.0001 arcseconds.
    private struct Term {
        let d, m, mp, f, omega: Double
        let psi0, psiT, eps0, epsT: Double
    }

    private static let terms: [Term] = [
        Term(d: 0, m: 0, mp: 0, f: 0, omega: 1, psi0: -171_996, psiT: -174.2, eps0: 92_025, epsT: 8.9),
        Term(d: -2, m: 0, mp: 0, f: 2, omega: 2, psi0: -13_187, psiT: -1.6, eps0: 5_736, epsT: -3.1),
        Term(d: 0, m: 0, mp: 0, f: 2, omega: 2, psi0: -2_274, psiT: -0.2, eps0: 977, epsT: -0.5),
        Term(d: 0, m: 0, mp: 0, f: 0, omega: 2, psi0: 2_062, psiT: 0.2, eps0: -895, epsT: 0.5),
        Term(d: 0, m: 1, mp: 0, f: 0, omega: 0, psi0: 1_426, psiT: -3.4, eps0: 54, epsT: -0.1),
        Term(d: 0, m: 0, mp: 1, f: 0, omega: 0, psi0: 712, psiT: 0.1, eps0: -7, epsT: 0),
        Term(d: -2, m: 1, mp: 0, f: 2, omega: 2, psi0: -517, psiT: 1.2, eps0: 224, epsT: -0.6),
        Term(d: 0, m: 0, mp: 0, f: 2, omega: 1, psi0: -386, psiT: -0.4, eps0: 200, epsT: 0),
        Term(d: 0, m: 0, mp: 1, f: 2, omega: 2, psi0: -301, psiT: 0, eps0: 129, epsT: -0.1),
        Term(d: -2, m: -1, mp: 0, f: 2, omega: 2, psi0: 217, psiT: -0.5, eps0: -95, epsT: 0.3),
        Term(d: -2, m: 0, mp: 1, f: 0, omega: 0, psi0: -158, psiT: 0, eps0: 0, epsT: 0),
        Term(d: -2, m: 0, mp: 0, f: 2, omega: 1, psi0: 129, psiT: 0.1, eps0: -70, epsT: 0),
        Term(d: 0, m: 0, mp: -1, f: 2, omega: 2, psi0: 123, psiT: 0, eps0: -53, epsT: 0),
    ]

    /// Nutation for a given Julian Date.
    static func nutation(julianDate jd: Double) -> Result {
        let t = AstroTime.julianCenturies(julianDate: jd)

        // Fundamental arguments (degrees), Meeus eq. 22.
        let d = 297.85036 + 445_267.111480 * t - 0.0019142 * t * t + t * t * t / 189_474.0
        let m = 357.52772 + 35_999.050340 * t - 0.0001603 * t * t - t * t * t / 300_000.0
        let mp = 134.96298 + 477_198.867398 * t + 0.0086972 * t * t + t * t * t / 56_250.0
        let f = 93.27191 + 483_202.017538 * t - 0.0036825 * t * t + t * t * t / 327_270.0
        let omega = 125.04452 - 1_934.136261 * t + 0.0020708 * t * t + t * t * t / 450_000.0

        var deltaPsi = 0.0   // units 0.0001″
        var deltaEps = 0.0
        for term in terms {
            let argDegrees = term.d * d + term.m * m + term.mp * mp + term.f * f + term.omega * omega
            let arg = argDegrees * AstroMath.degToRad
            deltaPsi += (term.psi0 + term.psiT * t) * sin(arg)
            deltaEps += (term.eps0 + term.epsT * t) * cos(arg)
        }

        // 0.0001″ → radians.
        let toRadians = 0.0001 / 3600.0 * AstroMath.degToRad
        return Result(longitude: deltaPsi * toRadians, obliquity: deltaEps * toRadians)
    }
}
