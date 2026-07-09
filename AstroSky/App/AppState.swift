//
//  AppState.swift
//  AstroSky
//
//  Central observable state: catalog, services, simulated time,
//  display settings and the current selection.
//

import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AppState {
    // MARK: Services & data

    let catalog = SkyCatalog()
    let satelliteService = SatelliteService()
    let locationService = LocationService()

    var observer: Observer { locationService.observer }

    // MARK: Time travel

    /// Offset applied to the wall clock, seconds. 0 = live sky.
    var timeOffset: TimeInterval = 0
    var isLiveTime: Bool { abs(timeOffset) < 1 }

    /// The instant the sky is being rendered for.
    var skyDate: Date { Date().addingTimeInterval(timeOffset) }
    var skyJulianDate: Double { AstroTime.julianDate(skyDate) }

    func resetToLiveTime() { timeOffset = 0 }

    // MARK: Selection & navigation

    /// Object currently shown in the info card / detail sheet.
    var selectedObjectID: String?
    /// Object the AR view should guide the user toward.
    var guideTargetID: String?
    /// Requests the Sky tab to become active (used by "Find in AR").
    var skyTabRequested = false

    func select(_ object: (any CelestialObject)?) {
        selectedObjectID = object?.id
    }

    var selectedObject: (any CelestialObject)? {
        selectedObjectID.flatMap { object(withID: $0) }
    }

    var guideTarget: (any CelestialObject)? {
        guideTargetID.flatMap { object(withID: $0) }
    }

    /// Unified lookup across the catalog and live satellites.
    func object(withID id: String) -> (any CelestialObject)? {
        if id.hasPrefix("sat.") {
            return satelliteService.satellite(withID: id)
        }
        return catalog.object(withID: id)
    }

    /// Unified search across the catalog and live satellites.
    func search(_ query: String) -> [any CelestialObject] {
        var results = catalog.search(query)
        results.append(contentsOf: satelliteService.search(query).map { $0 as any CelestialObject })
        return results
    }

    // MARK: Display settings (persisted)

    var showConstellationLines: Bool {
        get { access(keyPath: \.showConstellationLines); return defaults(bool: "showConstellationLines", default: true) }
        set { withMutation(keyPath: \.showConstellationLines) { UserDefaults.standard.set(newValue, forKey: "showConstellationLines") } }
    }

    var showLabels: Bool {
        get { access(keyPath: \.showLabels); return defaults(bool: "showLabels", default: true) }
        set { withMutation(keyPath: \.showLabels) { UserDefaults.standard.set(newValue, forKey: "showLabels") } }
    }

    var showSatellites: Bool {
        get { access(keyPath: \.showSatellites); return defaults(bool: "showSatellites", default: true) }
        set { withMutation(keyPath: \.showSatellites) { UserDefaults.standard.set(newValue, forKey: "showSatellites") } }
    }

    var showStarlink: Bool {
        get { access(keyPath: \.showStarlink); return defaults(bool: "showStarlink", default: false) }
        set { withMutation(keyPath: \.showStarlink) { UserDefaults.standard.set(newValue, forKey: "showStarlink") } }
    }

    var showDeepSky: Bool {
        get { access(keyPath: \.showDeepSky); return defaults(bool: "showDeepSky", default: true) }
        set { withMutation(keyPath: \.showDeepSky) { UserDefaults.standard.set(newValue, forKey: "showDeepSky") } }
    }

    var nightMode: Bool {
        get { access(keyPath: \.nightMode); return defaults(bool: "nightMode", default: false) }
        set { withMutation(keyPath: \.nightMode) { UserDefaults.standard.set(newValue, forKey: "nightMode") } }
    }

    /// Faintest star magnitude rendered in AR.
    var magnitudeLimit: Double {
        get {
            access(keyPath: \.magnitudeLimit)
            let stored = UserDefaults.standard.double(forKey: "magnitudeLimit")
            return stored == 0 ? 5.5 : stored
        }
        set { withMutation(keyPath: \.magnitudeLimit) { UserDefaults.standard.set(newValue, forKey: "magnitudeLimit") } }
    }

    private func defaults(bool key: String, default defaultValue: Bool) -> Bool {
        if UserDefaults.standard.object(forKey: key) == nil { return defaultValue }
        return UserDefaults.standard.bool(forKey: key)
    }

    // MARK: Lifecycle

    func start() {
        locationService.requestLocation()
        Task { await satelliteService.start() }
    }
}
