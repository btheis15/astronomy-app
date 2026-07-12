//
//  AppStatePersistenceTests.swift
//  AstroSkyTests
//
//  Tests for AppState UserDefaults persistence: verify that display settings
//  survive across AppState instances and that defaults are sane on first launch.
//

import Foundation
import Testing
@testable import AstroSky

@MainActor
struct AppStatePersistenceTests {

    // MARK: - Boolean toggle round-trips

    @Test func nightModePersists() {
        let original = UserDefaults.standard.bool(forKey: "nightMode")

        let state = AppState()
        state.nightMode = !original
        let reloaded = AppState()
        #expect(reloaded.nightMode == !original,
                "nightMode should survive AppState re-init via UserDefaults")

        // Restore
        state.nightMode = original
    }

    @Test func showConstellationLinesPersists() {
        let state = AppState()
        let flipped = !state.showConstellationLines
        state.showConstellationLines = flipped
        #expect(AppState().showConstellationLines == flipped)
        state.showConstellationLines = !flipped
    }

    @Test func showLabelsPersists() {
        let state = AppState()
        let flipped = !state.showLabels
        state.showLabels = flipped
        #expect(AppState().showLabels == flipped)
        state.showLabels = !flipped
    }

    // MARK: - Float / Double round-trips

    @Test func skyAlignmentOffsetPersists() {
        let state = AppState()
        state.skyAlignmentOffset = 0.314
        let loaded = AppState()
        #expect(abs(loaded.skyAlignmentOffset - 0.314) < 0.001,
                "skyAlignmentOffset should round-trip through UserDefaults")
        state.skyAlignmentOffset = 0
    }

    @Test func magnitudeLimitPersists() {
        let state = AppState()
        let testVal = 4.5
        state.magnitudeLimit = testVal
        let loaded = AppState()
        #expect(abs(loaded.magnitudeLimit - testVal) < 0.01,
                "magnitudeLimit should persist")
        state.magnitudeLimit = 5.5   // restore default
    }

    @Test func bortleClassPersists() {
        let state = AppState()
        state.bortleClass = 7
        let loaded = AppState()
        #expect(loaded.bortleClass == 7, "bortleClass should persist")
        state.bortleClass = 4   // restore default
    }

    // MARK: - Derived state

    @Test func bortleLimitingMagnitudeIsDerivedFromClass() {
        let state = AppState()
        state.bortleClass = 1   // darkest sky
        let darkMag = state.bortleLimitingMagnitude
        state.bortleClass = 9   // brightest sky
        let brightMag = state.bortleLimitingMagnitude
        #expect(darkMag > brightMag,
                "Bortle 1 (dark sky) should have higher limiting magnitude than Bortle 9")
        state.bortleClass = 4
    }

    @Test func hasAlignmentOffsetFalseWhenZero() {
        let state = AppState()
        state.skyAlignmentOffset = 0
        #expect(!state.hasAlignmentOffset)
        state.skyAlignmentOffset = 0.5
        #expect(state.hasAlignmentOffset)
        state.skyAlignmentOffset = 0
    }

    @Test func resetAlignmentClearsOffset() {
        let state = AppState()
        state.skyAlignmentOffset = 1.0
        state.resetAlignment()
        #expect(state.skyAlignmentOffset == 0)
        #expect(!state.hasAlignmentOffset)
    }

    // MARK: - Session queue (in-memory)

    @Test func sessionQueueAddRemove() {
        let state = AppState()
        let testID = "star.test.persistence.abc"
        #expect(!state.isInSessionQueue(testID))

        state.addToSessionQueue(testID)
        #expect(state.isInSessionQueue(testID))
        #expect(state.sessionQueue.contains(testID))

        state.removeFromSessionQueue(testID)
        #expect(!state.isInSessionQueue(testID))
    }

    @Test func sessionQueueNoDuplicates() {
        let state = AppState()
        let testID = "star.test.nodup.abc"
        state.addToSessionQueue(testID)
        state.addToSessionQueue(testID)
        let count = state.sessionQueue.filter { $0 == testID }.count
        #expect(count == 1, "Adding the same ID twice should not duplicate it")
        state.removeFromSessionQueue(testID)
    }

    @Test func sessionQueueOrderPreserved() {
        let state = AppState()
        let ids = ["star.test.order.1", "star.test.order.2", "star.test.order.3"]
        ids.forEach { state.addToSessionQueue($0) }
        let stored = state.sessionQueue.filter { ids.contains($0) }
        #expect(stored == ids, "Session queue should preserve insertion order")
        ids.forEach { state.removeFromSessionQueue($0) }
    }
}
