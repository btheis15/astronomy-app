//
//  SkyCatalog.swift
//  AstroSky
//
//  Aggregates every object source (solar system, stars, deep sky) and
//  provides unified search. Satellites live in SatelliteService because they
//  are fetched at runtime; AppState merges them into search results.
//

import Foundation

struct SkyCatalog {
    /// Stars used for rendering & search: HYG database if bundled,
    /// otherwise the embedded bright-star catalog.
    let stars: [Star]
    /// True when the deep HYG catalog was loaded from the bundle.
    let usesDeepCatalog: Bool

    let sun = SunObject()
    let moon = MoonObject()
    let planets = PlanetObject.all
    let deepSky = MessierCatalog.objects
    let constellations = ConstellationCatalog.constellations

    init() {
        if let deep = HYGCatalogLoader.loadIfAvailable() {
            // Keep the curated bright stars (they carry the keys used by
            // constellation figures) and add HYG stars below the embedded
            // catalog's magnitude floor.
            let embedded = StarCatalog.stars
            let embeddedFloor = embedded.map(\.visualMagnitude).max() ?? 4.0
            let extras = deep.filter { $0.visualMagnitude > embeddedFloor }
            self.stars = (embedded + extras).sorted { $0.visualMagnitude < $1.visualMagnitude }
            self.usesDeepCatalog = true
        } else {
            self.stars = StarCatalog.stars
            self.usesDeepCatalog = false
        }
    }

    /// All searchable objects (excluding satellites, which AppState adds).
    var allObjects: [any CelestialObject] {
        var objects: [any CelestialObject] = [sun, moon]
        objects.append(contentsOf: planets.map { $0 as any CelestialObject })
        objects.append(contentsOf: StarCatalog.stars.map { $0 as any CelestialObject })
        objects.append(contentsOf: deepSky.map { $0 as any CelestialObject })
        return objects
    }

    /// Case/diacritic-insensitive search over names, designations and types.
    func search(_ query: String) -> [any CelestialObject] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        func matches(_ object: any CelestialObject) -> Bool {
            object.name.localizedCaseInsensitiveContains(trimmed)
                || object.subtitle.localizedCaseInsensitiveContains(trimmed)
                || object.id.localizedCaseInsensitiveContains(trimmed)
        }

        var results = allObjects.filter(matches)

        // "M31", "M 31" and "31" match Messier designations.
        let compact = trimmed.replacingOccurrences(of: " ", with: "").lowercased()
        if compact.hasPrefix("m"), let number = Int(compact.dropFirst()),
           let messier = MessierCatalog.objectsByNumber[number],
           !results.contains(where: { $0.id == messier.id }) {
            results.insert(messier, at: 0)
        }

        // Rank: brighter objects first, prefix matches before contains.
        return results.sorted { a, b in
            let aPrefix = a.name.lowercased().hasPrefix(trimmed.lowercased())
            let bPrefix = b.name.lowercased().hasPrefix(trimmed.lowercased())
            if aPrefix != bPrefix { return aPrefix }
            return (a.magnitude ?? 99) < (b.magnitude ?? 99)
        }
    }

    /// Find an object by its stable identifier.
    func object(withID id: String) -> (any CelestialObject)? {
        allObjects.first { $0.id == id }
    }
}
