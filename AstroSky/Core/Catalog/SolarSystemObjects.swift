//
//  SolarSystemObjects.swift
//  AstroSky
//
//  CelestialObject wrappers for the Sun, the Moon and the planets.
//

import Foundation

// MARK: - Sun

struct SunObject: CelestialObject, Sendable {
    var id: String { "sun" }
    var name: String { "Sun" }
    var subtitle: String { "The star of the Solar System" }
    var kind: CelestialObjectKind { .sun }
    var magnitude: Double? { -26.7 }

    func skyPosition(julianDate jd: Double, observer: Observer) -> SkyPosition {
        let position = SunEphemeris.position(julianDate: jd)
        // The ephemeris returns equinox-of-date coordinates; rotate back to
        // J2000 for the shared frame (transpose of the precession matrix).
        let pMatrix = CoordinateTransforms.precessionMatrixFromJ2000(julianDate: jd)
        let vDate = position.equatorial.unitVector
        let vJ2000 = pMatrix.transpose * vDate
        let eqJ2000 = EquatorialCoordinates(rightAscension: atan2(vJ2000.y, vJ2000.x),
                                            declination: asin(min(1, max(-1, vJ2000.z))))
        let horizontal = CoordinateTransforms.horizontal(of: position.equatorial,
                                                         julianDate: jd,
                                                         observer: observer)
        return SkyPosition(equatorialJ2000: eqJ2000,
                           horizontal: horizontal,
                           distanceDescription: AstroFormat.distanceAU(position.distanceAU))
    }

    func infoRows(julianDate jd: Double, observer: Observer) -> [(label: String, value: String)] {
        let position = SunEphemeris.position(julianDate: jd)
        let angular = 2.0 * atan(696_000.0 / (position.distanceAU * AstroMath.auKilometers))
        return [
            ("Magnitude", "−26.7"),
            ("Distance", AstroFormat.distanceAU(position.distanceAU)),
            ("Angular size", AstroFormat.angularSize(angular)),
            ("Spectral type", "G2V — yellow dwarf"),
        ]
    }
}

// MARK: - Moon

struct MoonObject: CelestialObject, Sendable {
    var id: String { "moon" }
    var name: String { "Moon" }
    var subtitle: String { "Earth's natural satellite" }
    var kind: CelestialObjectKind { .moon }
    var magnitude: Double? { -12.7 }

    func skyPosition(julianDate jd: Double, observer: Observer) -> SkyPosition {
        let position = MoonEphemeris.position(julianDate: jd)
        let pMatrix = CoordinateTransforms.precessionMatrixFromJ2000(julianDate: jd)
        let vJ2000 = pMatrix.transpose * position.equatorial.unitVector
        let eqJ2000 = EquatorialCoordinates(rightAscension: atan2(vJ2000.y, vJ2000.x),
                                            declination: asin(min(1, max(-1, vJ2000.z))))
        let horizontal = CoordinateTransforms.horizontal(of: position.equatorial,
                                                         julianDate: jd,
                                                         observer: observer)
        return SkyPosition(equatorialJ2000: eqJ2000,
                           horizontal: horizontal,
                           distanceDescription: AstroFormat.distanceKm(position.distanceKm))
    }

    func infoRows(julianDate jd: Double, observer: Observer) -> [(label: String, value: String)] {
        let position = MoonEphemeris.position(julianDate: jd)
        let phase = MoonEphemeris.phase(julianDate: jd)
        return [
            ("Phase", phase.phaseName),
            ("Illumination", String(format: "%.0f%%", phase.illuminatedFraction * 100)),
            ("Distance", AstroFormat.distanceKm(position.distanceKm)),
            ("Angular size", AstroFormat.angularSize(MoonEphemeris.angularDiameter(distanceKm: position.distanceKm))),
        ]
    }
}

// MARK: - Planet

struct PlanetObject: CelestialObject, Identifiable, Sendable {
    let planet: Planet

    var id: String { "planet.\(planet.rawValue)" }
    var name: String { planet.name }
    var subtitle: String { "Planet \(planet.symbol)" }
    var kind: CelestialObjectKind { .planet }

    var magnitude: Double? {
        PlanetEphemeris.position(of: planet, julianDate: AstroTime.julianDate(Date())).magnitude
    }

    func skyPosition(julianDate jd: Double, observer: Observer) -> SkyPosition {
        let position = PlanetEphemeris.position(of: planet, julianDate: jd)
        return SkyPosition(equatorialJ2000: position.equatorialJ2000,
                           horizontal: horizontalFromJ2000(position.equatorialJ2000,
                                                           julianDate: jd,
                                                           observer: observer),
                           distanceDescription: AstroFormat.distanceAU(position.distanceAU))
    }

    func infoRows(julianDate jd: Double, observer: Observer) -> [(label: String, value: String)] {
        let position = PlanetEphemeris.position(of: planet, julianDate: jd)
        return [
            ("Magnitude", AstroFormat.magnitude(position.magnitude)),
            ("Distance from Earth", AstroFormat.distanceAU(position.distanceAU)),
            ("Distance from Sun", AstroFormat.distanceAU(position.heliocentricDistanceAU)),
            ("Angular size", AstroFormat.angularSize(position.angularDiameter)),
            ("Phase angle", String(format: "%.0f°", position.phaseAngle * AstroMath.radToDeg)),
        ]
    }

    static let all: [PlanetObject] = Planet.visible.map { PlanetObject(planet: $0) }
}
