//
//  ObjectImagery.swift
//  AstroSky
//
//  Real reference photographs for catalog objects: deep-sky images fetched from
//  Wikimedia Commons (NASA/ESA & contributors) via Scripts/fetch_object_images.sh
//  and bundled in ObjectImages/, plus the bundled 2K planet/Moon/Sun maps. Used
//  to show "what it really looks like" alongside the simulated eyepiece view.
//

import UIKit

enum ObjectImagery {
    /// A real photo for the object, if one is bundled.
    static func image(for object: any CelestialObject) -> UIImage? {
        guard let resource = resource(for: object) else { return nil }
        return load(key: resource.key, subdir: resource.subdir)
    }

    static func hasImage(for object: any CelestialObject) -> Bool {
        resource(for: object).map { load(key: $0.key, subdir: $0.subdir) != nil } ?? false
    }

    /// Short credit line shown wherever the photos appear.
    static let attribution = "Deep-sky photos: Wikimedia Commons (NASA / ESA & contributors). Planet maps: Solar System Scope (CC BY 4.0)."

    // MARK: Mapping

    private static func resource(for object: any CelestialObject) -> (key: String, subdir: String)? {
        switch object {
        case let deepSky as DeepSkyObject:
            return (deepSky.id, "ObjectImages")
        case let planet as PlanetObject:
            return (planetTextureKey(planet.planet), "Textures")
        case is MoonObject:
            return ("2k_moon", "Textures")
        case is SunObject:
            return ("2k_sun", "Textures")
        default:
            return nil
        }
    }

    /// Bundled 2K texture key per planet (kept in sync with the Sky markers).
    private static func planetTextureKey(_ planet: Planet) -> String {
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

    // MARK: Loading (robust to how the bundler lays resources out)

    private static func load(key: String, subdir: String) -> UIImage? {
        for ext in ["jpg", "png"] {
            if let url = Bundle.main.url(forResource: key, withExtension: ext, subdirectory: subdir),
               let image = UIImage(contentsOfFile: url.path) {
                return image
            }
            if let url = Bundle.main.url(forResource: key, withExtension: ext),
               let image = UIImage(contentsOfFile: url.path) {
                return image
            }
        }
        return UIImage(named: key)
    }
}
