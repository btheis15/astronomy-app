//
//  AstroMath.swift
//  AstroSky
//
//  Small math helpers shared by the astronomy engine.
//

import Foundation

enum AstroMath {
    static let degToRad = Double.pi / 180.0
    static let radToDeg = 180.0 / Double.pi
    static let hoursToRad = Double.pi / 12.0
    static let radToHours = 12.0 / Double.pi
    static let twoPi = 2.0 * Double.pi

    /// Astronomical unit in kilometers (IAU 2012).
    static let auKilometers = 149_597_870.7

    /// Normalize an angle in radians to [0, 2π).
    static func normalizedRadians(_ angle: Double) -> Double {
        var a = angle.truncatingRemainder(dividingBy: twoPi)
        if a < 0 { a += twoPi }
        return a
    }

    /// Normalize an angle in degrees to [0, 360).
    static func normalizedDegrees(_ angle: Double) -> Double {
        var a = angle.truncatingRemainder(dividingBy: 360.0)
        if a < 0 { a += 360.0 }
        return a
    }

    /// Normalize an angle in radians to (-π, π].
    static func signedRadians(_ angle: Double) -> Double {
        var a = normalizedRadians(angle)
        if a > .pi { a -= twoPi }
        return a
    }

    /// Solve Kepler's equation E - e·sin(E) = M for the eccentric anomaly E.
    /// - Parameters:
    ///   - meanAnomaly: M in radians.
    ///   - eccentricity: orbital eccentricity (0 ≤ e < 1).
    /// - Returns: eccentric anomaly E in radians.
    static func solveKepler(meanAnomaly: Double, eccentricity e: Double) -> Double {
        let m = signedRadians(meanAnomaly)
        var eAnom = e < 0.8 ? m : .pi
        // Newton-Raphson; converges in a handful of iterations for e < 1.
        for _ in 0..<30 {
            let delta = (eAnom - e * sin(eAnom) - m) / (1 - e * cos(eAnom))
            eAnom -= delta
            if abs(delta) < 1e-12 { break }
        }
        return eAnom
    }
}
