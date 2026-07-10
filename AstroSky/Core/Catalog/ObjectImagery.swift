//
//  ObjectImagery.swift
//  AstroSky
//
//  Real reference photographs for catalog objects: deep-sky and bright-star
//  images fetched from Wikipedia/Wikimedia (NASA/ESA & contributors) via
//  Scripts/fetch_object_images.sh and bundled in ObjectImages/, plus the
//  bundled 2K planet/Moon/Sun maps. Images are decoded off the main thread,
//  downsampled to the requested size, and cached — so navigation stays smooth.
//

import ImageIO
import UIKit

enum ObjectImagery {
    // NSCache is documented thread-safe; the unchecked annotation is sound.
    nonisolated(unsafe) private static let cache = NSCache<NSString, UIImage>()

    /// Whether a bundled photo exists (cheap — no decode). Safe for layout.
    static func hasImage(for object: any CelestialObject) -> Bool {
        guard let r = resource(for: object) else { return false }
        return fileURL(key: r.key, subdir: r.subdir) != nil
    }

    /// Cached, downsampled photo. Decodes off the main thread on first request.
    /// Takes plain `Sendable` keys so callers can resolve the object on the main
    /// actor and hand off only value types.
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

    /// Small downsampled CGImage for a deep-sky object's AR sprite texture.
    /// Synchronous but cheap (256px from an ~800px source); the AR loader calls
    /// it after startup and yields between objects.
    static func thumbnailCGImage(deepSkyID id: String, maxPixel: CGFloat) -> CGImage? {
        guard let url = fileURL(key: id, subdir: "ObjectImages") else { return nil }
        return downsample(url: url, maxPixel: maxPixel)?.cgImage
    }

    /// Short credit line shown wherever the photos appear.
    static let attribution = "Deep-sky & star photos: Wikimedia Commons (NASA / ESA & contributors). Planet maps: Solar System Scope (CC BY 4.0)."

    // MARK: Mapping

    /// Bundled resource (key, subdirectory) for an object, if a photo exists.
    /// Synchronous and cheap — resolve on the main actor, then load async.
    static func resource(for object: any CelestialObject) -> (key: String, subdir: String)? {
        switch object {
        case let deepSky as DeepSkyObject:
            return (deepSky.id, "ObjectImages")
        case let star as Star:
            return ("star_\(star.key)", "ObjectImages")
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

    // MARK: Loading

    private static func fileURL(key: String, subdir: String) -> URL? {
        for ext in ["jpg", "png"] {
            if let url = Bundle.main.url(forResource: key, withExtension: ext, subdirectory: subdir) { return url }
            if let url = Bundle.main.url(forResource: key, withExtension: ext) { return url }
        }
        return nil
    }

    /// Decode + downsample with ImageIO so we never hold a full-size bitmap.
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
