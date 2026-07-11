//
//  FavoritesStore.swift
//  AstroSky
//
//  In-memory sets for favorited objects and satellites, persisted to
//  UserDefaults. Object favorites are keyed by CelestialObject.id;
//  satellite favorites by Satellite.id (prefix "sat.").
//

import Foundation
import Observation

@MainActor
@Observable
final class FavoritesStore {
    private(set) var objectIDs: Set<String>
    private(set) var satelliteIDs: Set<String>

    init() {
        let ud = UserDefaults.standard
        objectIDs = Set(ud.stringArray(forKey: "favoriteObjectIDs") ?? [])
        satelliteIDs = Set(ud.stringArray(forKey: "favoriteSatelliteIDs") ?? [])
    }

    func isFavorite(_ id: String) -> Bool { objectIDs.contains(id) }
    func isFavoriteSatellite(_ id: String) -> Bool { satelliteIDs.contains(id) }

    func toggle(_ id: String) {
        if objectIDs.contains(id) { objectIDs.remove(id) } else { objectIDs.insert(id) }
        UserDefaults.standard.set(Array(objectIDs), forKey: "favoriteObjectIDs")
    }

    func toggleSatellite(_ id: String) {
        if satelliteIDs.contains(id) { satelliteIDs.remove(id) } else { satelliteIDs.insert(id) }
        UserDefaults.standard.set(Array(satelliteIDs), forKey: "favoriteSatelliteIDs")
    }

    func objects(in catalog: SkyCatalog) -> [any CelestialObject] {
        objectIDs.sorted().compactMap { catalog.object(withID: $0) }
    }
}
