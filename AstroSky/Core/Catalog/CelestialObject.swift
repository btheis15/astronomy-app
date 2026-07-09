//
//  CelestialObject.swift
//  AstroSky
//
//  The unified object model: everything the app can show — stars, planets,
//  the Sun and Moon, deep-sky objects and satellites — presents itself
//  through this protocol so that search, detail views, and the AR scene can
//  treat them uniformly.
//

import Foundation

enum CelestialObjectKind: String, Sendable {
    case star = "Star"
    case planet = "Planet"
    case sun = "Sun"
    case moon = "Moon"
    case deepSky = "Deep Sky"
    case satellite = "Satellite"

    var iconSystemName: String {
        switch self {
        case .star: "star.fill"
        case .planet: "circle.fill"
        case .sun: "sun.max.fill"
        case .moon: "moon.fill"
        case .deepSky: "sparkles"
        case .satellite: "antenna.radiowaves.left.and.right"
        }
    }
}

/// A computed sky position at a specific instant for a specific observer.
struct SkyPosition {
    /// Equatorial coordinates in the J2000 frame (what the AR scene uses).
    var equatorialJ2000: EquatorialCoordinates
    /// Horizontal coordinates for the observer (true altitude, no refraction).
    var horizontal: HorizontalCoordinates
    /// Display string for the object's distance, if meaningful.
    var distanceDescription: String?
}

protocol CelestialObject {
    /// Stable unique identifier, e.g. "star.sirius", "planet.mars", "m031".
    var id: String { get }
    var name: String { get }
    /// Secondary line, e.g. "α Canis Majoris · Canis Major".
    var subtitle: String { get }
    var kind: CelestialObjectKind { get }
    /// Apparent visual magnitude if defined (satellites: typical magnitude).
    var magnitude: Double? { get }

    /// Position at a given instant for a given observer.
    func skyPosition(julianDate jd: Double, observer: Observer) -> SkyPosition

    /// Label/value rows for the detail view (physical data etc.).
    func infoRows(julianDate jd: Double, observer: Observer) -> [(label: String, value: String)]
}

extension CelestialObject {
    /// Horizontal coordinates convenience.
    func horizontal(julianDate jd: Double, observer: Observer) -> HorizontalCoordinates {
        skyPosition(julianDate: jd, observer: observer).horizontal
    }

    /// Shared helper: J2000 equatorial → precessed-to-date → horizontal.
    func horizontalFromJ2000(_ eq: EquatorialCoordinates,
                             julianDate jd: Double,
                             observer: Observer) -> HorizontalCoordinates {
        let ofDate = CoordinateTransforms.precessFromJ2000(eq, julianDate: jd)
        return CoordinateTransforms.horizontal(of: ofDate, julianDate: jd, observer: observer)
    }
}
