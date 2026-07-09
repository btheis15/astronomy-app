//
//  AngularSize.swift
//  AstroSky
//
//  Unified apparent angular size (radians) for anything worth pointing a
//  telescope at, so the eyepiece preview treats every object the same way.
//

import Foundation

enum AngularSizeSource {
    /// Apparent angular size in radians, or nil for effectively point sources
    /// (stars) where magnification doesn't enlarge the object.
    static func angularSizeRadians(for object: any CelestialObject, julianDate jd: Double) -> Double? {
        switch object {
        case let planet as PlanetObject:
            return PlanetEphemeris.position(of: planet.planet, julianDate: jd).angularDiameter
        case is MoonObject:
            let distance = MoonEphemeris.position(julianDate: jd).distanceKm
            return MoonEphemeris.angularDiameter(distanceKm: distance)
        case is SunObject:
            let distanceAU = SunEphemeris.position(julianDate: jd).distanceAU
            return 2.0 * atan(696_000.0 / (distanceAU * AstroMath.auKilometers))
        case let minor as MinorBodyObject:
            // Asteroids are effectively point-like in amateur scopes.
            _ = minor
            return nil
        case let deepSky as DeepSkyObject:
            let arcmin = DeepSkySizes.angularSizeArcmin(for: deepSky)
                ?? DeepSkySizes.fallbackArcmin(type: deepSky.type, magnitude: deepSky.visualMagnitude)
            return arcmin / 60.0 * AstroMath.degToRad
        default:
            return nil   // stars, satellites
        }
    }

    /// Whether the catalogued size is a real value (vs an estimate) — for a
    /// small "size estimated" hint in the UI.
    static func hasMeasuredSize(_ object: any CelestialObject) -> Bool {
        if let deepSky = object as? DeepSkyObject {
            return DeepSkySizes.angularSizeArcmin(for: deepSky) != nil
        }
        return true   // solar-system sizes are computed exactly
    }
}
