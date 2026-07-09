//
//  ScaleModelMath.swift
//  AstroSky
//
//  Pure scaling for the AR models: sizes are always proportional; distances can
//  be true-to-scale or compressed so satellites stay visible together.
//

import Foundation

enum DistanceMode: String, CaseIterable, Sendable {
    case fit        // compressed (log) spacing — everything visible together
    case trueScale  // real orbital distances at the same scale as the sizes

    var title: String { self == .fit ? "Fit to view" : "True scale" }
}

enum ScaleModelMath {
    /// Never-smaller-than this so tiny moons remain tappable (meters).
    static let minRadiusMeters = 0.006

    /// Meters-per-kilometer so the primary body renders at `targetMeters` radius.
    static func sceneScale(primaryRadiusKm: Double, targetMeters: Double) -> Double {
        primaryRadiusKm > 0 ? targetMeters / primaryRadiusKm : 0
    }

    /// Drawn radius (meters) for a body, clamped to a visible minimum.
    static func bodyRadiusMeters(km: Double, scale: Double) -> Double {
        max(minRadiusMeters, km * scale)
    }

    /// Distance (meters) from the primary at which to place a satellite.
    /// - `trueScale`: real orbit × scale.
    /// - `fit`: log-compressed spacing anchored so the nearest sits just outside
    ///   the primary and the farthest is still within arm's reach.
    static func distanceMeters(orbitKm: Double, primaryRadiusMeters: Double,
                               scale: Double, mode: DistanceMode,
                               satelliteIndex: Int, satelliteCount: Int) -> Double {
        switch mode {
        case .trueScale:
            return orbitKm * scale
        case .fit:
            // Even log-ish rings: primary radius + a growing gap per satellite.
            let base = primaryRadiusMeters * 1.6
            let step = primaryRadiusMeters * 0.9
            return base + step * Double(satelliteIndex + 1)
        }
    }
}
