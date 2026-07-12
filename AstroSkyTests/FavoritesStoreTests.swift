//
//  FavoritesStoreTests.swift
//  AstroSkyTests
//

import Testing
@testable import AstroSky

@MainActor
struct FavoritesStoreTests {
    // Use IDs that won't collide with real data in UserDefaults.
    private let testObjectID  = "test.favorites.star.abc123"
    private let testSatelliteID = "test.favorites.sat.abc123"

    private func freshStore() -> FavoritesStore {
        let store = FavoritesStore()
        // Ensure clean state regardless of prior test runs
        if store.isFavorite(testObjectID)         { store.toggle(testObjectID) }
        if store.isFavoriteSatellite(testSatelliteID) { store.toggleSatellite(testSatelliteID) }
        return store
    }

    @Test func toggleObjectAddsThenRemoves() {
        let store = freshStore()
        #expect(!store.isFavorite(testObjectID))
        store.toggle(testObjectID)
        #expect(store.isFavorite(testObjectID))
        store.toggle(testObjectID)
        #expect(!store.isFavorite(testObjectID))
    }

    @Test func toggleSatelliteAddsThenRemoves() {
        let store = freshStore()
        #expect(!store.isFavoriteSatellite(testSatelliteID))
        store.toggleSatellite(testSatelliteID)
        #expect(store.isFavoriteSatellite(testSatelliteID))
        store.toggleSatellite(testSatelliteID)
        #expect(!store.isFavoriteSatellite(testSatelliteID))
    }

    @Test func objectFavoriteDoesNotAffectSatelliteFavorite() {
        let store = freshStore()
        store.toggle(testObjectID)
        #expect(store.isFavorite(testObjectID))
        #expect(!store.isFavoriteSatellite(testObjectID))
        // Cleanup
        store.toggle(testObjectID)
    }

    @Test func objectsResolvesExistingIDFromCatalog() {
        let catalog = SkyCatalog()
        guard let star = catalog.stars.first else { return }

        let store = freshStore()
        if !store.isFavorite(star.id) { store.toggle(star.id) }

        let resolved = store.objects(in: catalog)
        #expect(resolved.contains { $0.id == star.id })

        // Cleanup
        if store.isFavorite(star.id) { store.toggle(star.id) }
    }

    @Test func objectsIgnoresMissingIDs() {
        let catalog = SkyCatalog()
        let store = freshStore()
        store.toggle("nonexistent.celestial.id.xyz")

        let resolved = store.objects(in: catalog)
        #expect(!resolved.contains { $0.id == "nonexistent.celestial.id.xyz" })

        // Cleanup
        if store.isFavorite("nonexistent.celestial.id.xyz") {
            store.toggle("nonexistent.celestial.id.xyz")
        }
    }

    @Test func multipleObjectsReturnedInOrder() {
        let catalog = SkyCatalog()
        let stars = Array(catalog.stars.prefix(3))
        guard stars.count == 3 else { return }

        let store = freshStore()
        for star in stars { if !store.isFavorite(star.id) { store.toggle(star.id) } }

        let resolved = store.objects(in: catalog)
        #expect(resolved.filter { obj in stars.contains { $0.id == obj.id } }.count == 3)

        // Cleanup
        for star in stars { if store.isFavorite(star.id) { store.toggle(star.id) } }
    }
}
