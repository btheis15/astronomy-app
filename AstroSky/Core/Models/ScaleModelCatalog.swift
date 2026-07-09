//
//  ScaleModelCatalog.swift
//  AstroSky
//
//  Data for the Scale AR explorer: real radii and orbital distances for the
//  Sun, planets and their major moons, plus one-line facts. Sizes are always
//  drawn proportionally; distances can be shown true-to-scale or compressed.
//

import Foundation
import simd

struct ScaleBody: Identifiable, Sendable {
    let key: String
    let name: String
    let radiusKm: Double
    /// Orbital semi-major axis about its primary (km); nil for the primary body.
    let orbitRadiusKm: Double?
    /// Bundled texture base name (e.g. "2k_mars"), or nil to use a procedural map.
    let textureKey: String?
    /// Fallback/tint color for the procedural texture, RGB 0–1.
    let tint: SIMD3<Double>
    let hasRings: Bool
    let info: String

    var id: String { key }
}

enum ScaleScene: Identifiable, Hashable {
    case earthMoon
    case planet(Planet)
    case solarSystem
    case galaxy

    var id: String {
        switch self {
        case .earthMoon: "earthMoon"
        case .planet(let p): "planet.\(p.rawValue)"
        case .solarSystem: "solarSystem"
        case .galaxy: "galaxy"
        }
    }

    var title: String {
        switch self {
        case .earthMoon: "Earth & Moon"
        case .planet(let p): p.name
        case .solarSystem: "Solar System"
        case .galaxy: "Milky Way"
        }
    }

    static var all: [ScaleScene] {
        [.earthMoon] + Planet.allCases.filter { $0 != .earth }.map { ScaleScene.planet($0) }
            + [.solarSystem, .galaxy]
    }
}

enum ScaleModelCatalog {
    static let sunRadiusKm = 696_000.0

    /// Bodies making up a scene: element 0 is the primary, the rest are satellites.
    static func bodies(for scene: ScaleScene) -> [ScaleBody] {
        switch scene {
        case .earthMoon:
            return [earth, moon]
        case .planet(let planet):
            return [planetBody(planet)] + moons[planet, default: []]
        case .solarSystem:
            return [sun] + Planet.visible.map { solarSystemPlanet($0) }
        case .galaxy:
            return [milkyWay]
        }
    }

    // MARK: Primaries

    static let sun = ScaleBody(key: "sun", name: "Sun", radiusKm: sunRadiusKm, orbitRadiusKm: nil,
                               textureKey: "2k_sun", tint: SIMD3(1.0, 0.86, 0.4), hasRings: false,
                               info: "The Sun holds 99.8% of the Solar System's mass — about 1.3 million Earths would fit inside.")

    static let earth = ScaleBody(key: "earth", name: "Earth", radiusKm: 6378.1, orbitRadiusKm: nil,
                                 textureKey: "2k_earth_daymap", tint: SIMD3(0.25, 0.45, 0.75), hasRings: false,
                                 info: "Our home world — the only place known to harbor life, and the densest planet in the Solar System.")

    static let moon = ScaleBody(key: "moon", name: "Moon", radiusKm: 1737.4, orbitRadiusKm: 384_400,
                                textureKey: "2k_moon", tint: SIMD3(0.7, 0.7, 0.7), hasRings: false,
                                info: "About a quarter of Earth's diameter, it's the largest moon relative to its planet in the Solar System.")

    static let milkyWay = ScaleBody(key: "milkyway", name: "Milky Way", radiusKm: 4.7e17, orbitRadiusKm: nil,
                                    textureKey: "2k_stars_milky_way", tint: SIMD3(0.6, 0.65, 0.9), hasRings: false,
                                    info: "Our barred spiral galaxy — about 100,000 light-years across, home to a few hundred billion stars. The Sun sits ~26,000 ly from the center.")

    // MARK: Planet bodies

    private static func planetBody(_ planet: Planet) -> ScaleBody {
        ScaleBody(key: planet.rawValue, name: planet.name, radiusKm: planet.radiusKm, orbitRadiusKm: nil,
                  textureKey: textureKey(for: planet), tint: tint(for: planet),
                  hasRings: planet == .saturn, info: planetInfo[planet] ?? "")
    }

    private static func solarSystemPlanet(_ planet: Planet) -> ScaleBody {
        ScaleBody(key: planet.rawValue, name: planet.name, radiusKm: planet.radiusKm,
                  orbitRadiusKm: semiMajorAU(planet) * AstroMath.auKilometers,
                  textureKey: textureKey(for: planet), tint: tint(for: planet),
                  hasRings: planet == .saturn, info: planetInfo[planet] ?? "")
    }

    // MARK: Moons (radius km, orbital semi-major axis km)

    private static let moons: [Planet: [ScaleBody]] = [
        .mars: [
            moon("phobos", "Phobos", 11.3, 9_376, SIMD3(0.5, 0.45, 0.4), "A tiny, lumpy moon spiraling slowly toward Mars."),
            moon("deimos", "Deimos", 6.2, 23_463, SIMD3(0.5, 0.45, 0.4), "The smaller, outer Martian moon — barely 12 km across."),
        ],
        .jupiter: [
            moon("io", "Io", 1821.6, 421_700, SIMD3(0.9, 0.85, 0.5), "The most volcanically active body in the Solar System."),
            moon("europa", "Europa", 1560.8, 671_034, SIMD3(0.8, 0.8, 0.75), "An icy crust hides a global ocean — a prime target in the search for life."),
            moon("ganymede", "Ganymede", 2634.1, 1_070_412, SIMD3(0.6, 0.6, 0.55), "The largest moon in the Solar System — bigger than Mercury."),
            moon("callisto", "Callisto", 2410.3, 1_882_709, SIMD3(0.45, 0.4, 0.4), "One of the most heavily cratered worlds known."),
        ],
        .saturn: [
            moon("titan", "Titan", 2574.7, 1_221_870, SIMD3(0.85, 0.7, 0.35), "A hazy nitrogen atmosphere and lakes of liquid methane."),
            moon("rhea", "Rhea", 763.8, 527_108, SIMD3(0.7, 0.7, 0.7), "Saturn's second-largest moon — an icy, cratered world."),
        ],
        .uranus: [
            moon("titania", "Titania", 788.9, 435_910, SIMD3(0.6, 0.6, 0.62), "The largest moon of Uranus, scarred by huge canyons."),
            moon("oberon", "Oberon", 761.4, 583_520, SIMD3(0.55, 0.55, 0.58), "The outermost large Uranian moon."),
        ],
        .neptune: [
            moon("triton", "Triton", 1353.4, 354_759, SIMD3(0.75, 0.78, 0.8), "Orbits backwards and spews nitrogen geysers — likely a captured dwarf planet."),
        ],
    ]

    private static func moon(_ key: String, _ name: String, _ r: Double, _ a: Double,
                             _ tint: SIMD3<Double>, _ info: String) -> ScaleBody {
        ScaleBody(key: key, name: name, radiusKm: r, orbitRadiusKm: a,
                  textureKey: nil, tint: tint, hasRings: false, info: info)
    }

    // MARK: Per-planet appearance & facts

    private static func textureKey(for planet: Planet) -> String? {
        switch planet {
        case .mercury: "2k_mercury"
        case .venus: "2k_venus_atmosphere"
        case .earth: "2k_earth_daymap"
        case .mars: "2k_mars"
        case .jupiter: "2k_jupiter"
        case .saturn: "2k_saturn"
        case .uranus: "2k_uranus"
        case .neptune: "2k_neptune"
        }
    }

    private static func tint(for planet: Planet) -> SIMD3<Double> {
        switch planet {
        case .mercury: SIMD3(0.55, 0.52, 0.5)
        case .venus: SIMD3(0.9, 0.8, 0.55)
        case .earth: SIMD3(0.25, 0.45, 0.75)
        case .mars: SIMD3(0.8, 0.4, 0.25)
        case .jupiter: SIMD3(0.8, 0.7, 0.55)
        case .saturn: SIMD3(0.85, 0.75, 0.55)
        case .uranus: SIMD3(0.6, 0.85, 0.87)
        case .neptune: SIMD3(0.3, 0.45, 0.85)
        }
    }

    private static func semiMajorAU(_ planet: Planet) -> Double {
        switch planet {
        case .mercury: 0.387
        case .venus: 0.723
        case .earth: 1.0
        case .mars: 1.524
        case .jupiter: 5.203
        case .saturn: 9.537
        case .uranus: 19.19
        case .neptune: 30.07
        }
    }

    private static let planetInfo: [Planet: String] = [
        .mercury: "The smallest planet and closest to the Sun, with days hotter and nights colder than almost anywhere.",
        .venus: "A runaway greenhouse — its thick CO₂ atmosphere makes it the hottest planet, ~465 °C.",
        .earth: "Our home world — the only place known to harbor life.",
        .mars: "The Red Planet, rusted by iron oxide, with the tallest volcano in the Solar System.",
        .jupiter: "The giant — over 300 Earth masses, with a centuries-old storm, the Great Red Spot.",
        .saturn: "Famous for its bright ring system, made of countless ice and rock particles.",
        .uranus: "An ice giant tipped on its side, orbiting the Sun on its axis.",
        .neptune: "The windiest planet, with supersonic storms in its deep-blue atmosphere.",
    ]
}
