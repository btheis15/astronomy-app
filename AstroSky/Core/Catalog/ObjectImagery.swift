//
//  ObjectImagery.swift
//  AstroSky
//
//  Real photographs for catalog objects, as a small gallery per object so we
//  can show more than one source:
//   • a "telescope view" — a wide-field survey cutout (Pan-STARRS / DSS2 via
//     CDS hips2fits) framed to the object's true angular size, i.e. what it
//     actually looks like through a scope;
//   • a detail/beauty shot — NASA/ESA Hubble (Messier) or a Wikimedia photo.
//  Plus the bundled 2K planet/Moon/Sun maps. All decoded off the main thread,
//  downsampled and cached, so navigation stays smooth.
//

import ImageIO
import UIKit

/// One bundled photo of an object, with its own credit.
struct ObjectPhoto: Identifiable, Sendable {
    let key: String
    let subdir: String
    let caption: String
    let credit: String
    var id: String { key }
}

enum ObjectImagery {
    nonisolated(unsafe) private static let cache = NSCache<NSString, UIImage>()

    /// Ordered gallery of bundled photos for an object (empty if none).
    static func photos(for object: any CelestialObject) -> [ObjectPhoto] {
        switch object {
        case let deepSky as DeepSkyObject:
            var photos: [ObjectPhoto] = []
            // Beauty/detail shot first.
            if exists(deepSky.id, "ObjectImages") {
                let isHubble = hubbleMessierIDs.contains(deepSky.id)
                photos.append(ObjectPhoto(key: deepSky.id, subdir: "ObjectImages",
                                          caption: isHubble ? "Hubble" : "Photograph",
                                          credit: isHubble ? "NASA / ESA Hubble" : "Wikimedia Commons"))
            }
            // Wide-field "telescope view".
            if exists("\(deepSky.id)_wide", "ObjectImages") {
                photos.append(ObjectPhoto(key: "\(deepSky.id)_wide", subdir: "ObjectImages",
                                          caption: "Telescope view", credit: "DSS2 / Pan-STARRS (CDS)"))
            }
            return photos
        case let star as Star:
            return exists("star_\(star.key)", "ObjectImages")
                ? [ObjectPhoto(key: "star_\(star.key)", subdir: "ObjectImages",
                               caption: "Photograph", credit: "Wikimedia Commons")]
                : []
        case let planet as PlanetObject:
            let key = planetTextureKey(planet.planet)
            return [ObjectPhoto(key: key, subdir: "Textures", caption: "Surface map",
                                credit: "Solar System Scope (CC BY 4.0)")]
        case is MoonObject:
            return [ObjectPhoto(key: "2k_moon", subdir: "Textures", caption: "Surface map",
                                credit: "Solar System Scope (CC BY 4.0)")]
        case is SunObject:
            return [ObjectPhoto(key: "2k_sun", subdir: "Textures", caption: "Surface map",
                                credit: "Solar System Scope (CC BY 4.0)")]
        default:
            return []
        }
    }

    static func hasImage(for object: any CelestialObject) -> Bool {
        !photos(for: object).isEmpty
    }

    /// The most telescope-representative photo (the wide-field cutout if we have
    /// one), for the eyepiece side-by-side and AR sprite.
    static func telescopePhoto(for object: any CelestialObject) -> ObjectPhoto? {
        let all = photos(for: object)
        return all.first { $0.caption == "Telescope view" } ?? all.first
    }

    /// Cached, downsampled photo. Decodes off the main thread on first request.
    static func imageAsync(key: String, subdir: String, maxPixel: CGFloat) async -> UIImage? {
        let cacheKey = "\(key)@\(Int(maxPixel))" as NSString
        if let cached = cache.object(forKey: cacheKey) { return cached }
        guard let url = fileURL(key: key, subdir: subdir) else { return nil }
        let image = await Task.detached(priority: .userInitiated) {
            downsample(url: url, maxPixel: maxPixel)
        }.value
        if let image { cache.setObject(image, forKey: cacheKey) }
        return image
    }

    /// Small downsampled CGImage for a deep-sky object's AR sprite texture,
    /// preferring the wide-field cutout. Cheap; the AR loader yields between objects.
    static func thumbnailCGImage(deepSkyID id: String, maxPixel: CGFloat) -> CGImage? {
        let key = exists("\(id)_wide", "ObjectImages") ? "\(id)_wide" : id
        guard let url = fileURL(key: key, subdir: "ObjectImages") else { return nil }
        return downsample(url: url, maxPixel: maxPixel)?.cgImage
    }

    static let attribution = "Telescope-view images: DSS2 / Pan-STARRS (CDS). Messier detail: NASA / ESA Hubble. Other photos: Wikimedia Commons. Planet maps: Solar System Scope (CC BY 4.0)."

    // MARK: Mapping

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

    /// Messier objects whose primary photo comes from NASA's Hubble catalog.
    private static let hubbleMessierIDs: Set<String> = {
        let numbers = [1, 2, 3, 4, 5, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 19, 20, 22, 24,
                       27, 28, 30, 31, 32, 33, 35, 42, 43, 44, 45, 46, 48, 49, 51, 53, 54, 55,
                       56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 74,
                       75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92,
                       94, 95, 96, 98, 99, 100, 101, 102, 104, 105, 106, 107, 108, 109, 110]
        return Set(numbers.map { String(format: "m%03d", $0) })
    }()

    // MARK: Loading

    private static func exists(_ key: String, _ subdir: String) -> Bool {
        fileURL(key: key, subdir: subdir) != nil
    }

    private static func fileURL(key: String, subdir: String) -> URL? {
        for ext in ["jpg", "png"] {
            if let url = Bundle.main.url(forResource: key, withExtension: ext, subdirectory: subdir) { return url }
            if let url = Bundle.main.url(forResource: key, withExtension: ext) { return url }
        }
        return nil
    }

    private static func downsample(url: URL, maxPixel: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}
