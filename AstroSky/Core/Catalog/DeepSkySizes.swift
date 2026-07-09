//
//  DeepSkySizes.swift
//  AstroSky
//
//  Apparent angular sizes for deep-sky objects, keyed by object id so the data
//  stays additive (Messier now; Caldwell/NGC can be appended). Objects without
//  an entry fall back to a type/magnitude estimate.
//

import Foundation

enum DeepSkySizes {
    /// Major-axis apparent size in arcminutes, keyed by DeepSkyObject.id.
    static let majorAxisArcmin: [String: Double] = [
        "m001": 6, "m008": 90, "m011": 14, "m013": 20, "m016": 35, "m017": 46,
        "m020": 28, "m022": 24, "m027": 8, "m031": 178, "m033": 70, "m042": 85,
        "m044": 95, "m045": 110, "m051": 11, "m057": 1.4, "m063": 10, "m064": 10,
        "m065": 8, "m066": 9, "m074": 10, "m078": 8, "m081": 27, "m082": 11,
        "m083": 13, "m087": 7, "m092": 14, "m097": 3.4, "m101": 29, "m104": 9,
        "m106": 19, "m108": 8, "m109": 8, "m110": 22,
        "c014": 60, "c020": 60, "c033": 70, "c034": 60, "c041": 330, "c049": 80,
        "c077": 26, "c080": 36, "c092": 120,
        "ngc253": 27, "ngc891": 14, "ngc4565": 16, "ngc4631": 15, "ngc7000": 120,
        "ngc869": 30, "ngc2244": 24,
    ]

    /// Minor/major axis ratio for ellipse drawing (default from type otherwise).
    static let axisRatio: [String: Double] = [
        "m031": 0.30, "m104": 0.42, "m064": 0.55, "m081": 0.5, "m108": 0.25,
        "ngc4565": 0.12, "ngc891": 0.1, "ngc253": 0.25,
    ]

    /// Real catalogued size (arcminutes) if known, else nil.
    static func angularSizeArcmin(for object: DeepSkyObject) -> Double? {
        majorAxisArcmin[object.id]
    }

    /// Type/magnitude estimate when no catalogued size exists (cosmetic).
    static func fallbackArcmin(type: DeepSkyType, magnitude: Double) -> Double {
        let base: Double
        switch type {
        case .galaxy: base = 8
        case .globularCluster: base = 10
        case .openCluster: base = 25
        case .nebula: base = 20
        case .planetaryNebula: base = 1.5
        case .supernovaRemnant: base = 8
        case .starCloud: base = 60
        case .asterism: base = 30
        }
        let scale = min(1.5, max(0.4, 1.3 - 0.05 * (magnitude - 6)))
        return base * scale
    }

    /// Minor/major axis ratio (catalogued, else a per-type default).
    static func axisRatio(for object: DeepSkyObject) -> Double {
        if let ratio = axisRatio[object.id] { return ratio }
        switch object.type {
        case .galaxy: return 0.5
        default: return 1.0
        }
    }
}
