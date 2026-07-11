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

enum SkyDisplayMode: Int, Hashable {
    case ar = 0       // camera passthrough + ARKit motion tracking
    case vr = 1       // black background + gyroscope motion tracking
    case freeLook = 2 // black background + drag to look
}

@MainActor
@Observable
final class AppState {
    // MARK: Services & data

    var catalog = SkyCatalog()   // starts with embedded bright stars; upgraded async in start()
    let satelliteService = SatelliteService()
    let locationService = LocationService()
    let notificationScheduler = PassNotificationScheduler()
    let eventNotificationScheduler = EventNotificationScheduler()
    let equipment = EquipmentStore()
    let favorites = FavoritesStore()

    var observer: Observer { locationService.observer }

    // MARK: Persisted display settings (loaded in init)

    var showConstellationLines: Bool = true {
        didSet { UserDefaults.standard.set(showConstellationLines, forKey: "showConstellationLines") }
    }

    var showLabels: Bool = true {
        didSet { UserDefaults.standard.set(showLabels, forKey: "showLabels") }
    }

    var showSatellites: Bool = true {
        didSet { UserDefaults.standard.set(showSatellites, forKey: "showSatellites") }
    }

    var showStarlink: Bool = false {
        didSet { UserDefaults.standard.set(showStarlink, forKey: "showStarlink") }
    }

    var showDeepSky: Bool = true {
        didSet { UserDefaults.standard.set(showDeepSky, forKey: "showDeepSky") }
    }

    var nightMode: Bool = false {
        didSet { UserDefaults.standard.set(nightMode, forKey: "nightMode") }
    }

    var skyDisplayMode: SkyDisplayMode = .ar {
        didSet { UserDefaults.standard.set(skyDisplayMode.rawValue, forKey: "skyDisplayMode") }
    }

    var showMeteorShowers: Bool = true {
        didSet { UserDefaults.standard.set(showMeteorShowers, forKey: "showMeteorShowers") }
    }

    var showMilkyWay: Bool = true {
        didSet { UserDefaults.standard.set(showMilkyWay, forKey: "showMilkyWay") }
    }

    var showEcliptic: Bool = false {
        didSet { UserDefaults.standard.set(showEcliptic, forKey: "showEcliptic") }
    }

    var showCelestialEquator: Bool = false {
        didSet { UserDefaults.standard.set(showCelestialEquator, forKey: "showCelestialEquator") }
    }

    var showCoordinateGrid: Bool = false {
        didSet { UserDefaults.standard.set(showCoordinateGrid, forKey: "showCoordinateGrid") }
    }

    var hasOnboarded: Bool = false {
        didSet { UserDefaults.standard.set(hasOnboarded, forKey: "hasOnboarded") }
    }

    var bortleClass: Int = 4 {
        didSet {
            let clamped = min(9, max(1, bortleClass))
            guard clamped == bortleClass else {
                bortleClass = clamped   // re-fires didSet with the valid value, which writes UserDefaults
                return
            }
            UserDefaults.standard.set(bortleClass, forKey: "bortleClass")
        }
    }

    var magnitudeLimit: Double = 5.5 {
        didSet { UserDefaults.standard.set(magnitudeLimit, forKey: "magnitudeLimit") }
    }

    var passNotificationsEnabled: Bool = false {
        didSet { UserDefaults.standard.set(passNotificationsEnabled, forKey: "passNotificationsEnabled") }
    }

    var eventNotificationsEnabled: Bool = false {
        didSet { UserDefaults.standard.set(eventNotificationsEnabled, forKey: "eventNotificationsEnabled") }
    }

    init() {
        let ud = UserDefaults.standard

        // Load bool settings with proper nil checking
        showConstellationLines = ud.object(forKey: "showConstellationLines") == nil ? true : ud.bool(forKey: "showConstellationLines")
        showLabels = ud.object(forKey: "showLabels") == nil ? true : ud.bool(forKey: "showLabels")
        showSatellites = ud.object(forKey: "showSatellites") == nil ? true : ud.bool(forKey: "showSatellites")
        showStarlink = ud.object(forKey: "showStarlink") == nil ? false : ud.bool(forKey: "showStarlink")
        showDeepSky = ud.object(forKey: "showDeepSky") == nil ? true : ud.bool(forKey: "showDeepSky")
        nightMode = ud.object(forKey: "nightMode") == nil ? false : ud.bool(forKey: "nightMode")
        // Migrate from old preferManualSky bool if skyDisplayMode not yet stored.
        if ud.object(forKey: "skyDisplayMode") != nil {
            skyDisplayMode = SkyDisplayMode(rawValue: ud.integer(forKey: "skyDisplayMode")) ?? .ar
        } else {
            skyDisplayMode = ud.bool(forKey: "preferManualSky") ? .freeLook : .ar
        }
        showMeteorShowers = ud.object(forKey: "showMeteorShowers") == nil ? true : ud.bool(forKey: "showMeteorShowers")
        showMilkyWay = ud.object(forKey: "showMilkyWay") == nil ? true : ud.bool(forKey: "showMilkyWay")
        showEcliptic = ud.object(forKey: "showEcliptic") == nil ? false : ud.bool(forKey: "showEcliptic")
        showCelestialEquator = ud.object(forKey: "showCelestialEquator") == nil ? false : ud.bool(forKey: "showCelestialEquator")
        showCoordinateGrid = ud.object(forKey: "showCoordinateGrid") == nil ? false : ud.bool(forKey: "showCoordinateGrid")
        hasOnboarded = ud.object(forKey: "hasOnboarded") == nil ? false : ud.bool(forKey: "hasOnboarded")
        passNotificationsEnabled = ud.object(forKey: "passNotificationsEnabled") == nil ? false : ud.bool(forKey: "passNotificationsEnabled")
        eventNotificationsEnabled = ud.object(forKey: "eventNotificationsEnabled") == nil ? false : ud.bool(forKey: "eventNotificationsEnabled")
        skyAlignmentOffset = Float(ud.double(forKey: "skyAlignmentOffset"))

        // Load integer and double settings with zero-check for defaults
        let storedBortle = ud.integer(forKey: "bortleClass")
        bortleClass = storedBortle == 0 ? 4 : min(9, max(1, storedBortle))

        let storedMag = ud.double(forKey: "magnitudeLimit")
        magnitudeLimit = storedMag == 0 ? 5.5 : storedMag
    }

    // MARK: Time travel

    /// Offset applied to the wall clock, seconds. 0 = live sky.
    var timeOffset: TimeInterval = 0
    var isLiveTime: Bool { abs(timeOffset) < 1 }

    /// The instant the sky is being rendered for.
    var skyDate: Date { Date().addingTimeInterval(timeOffset) }
    var skyJulianDate: Double { AstroTime.julianDate(skyDate) }

    func resetToLiveTime() { timeOffset = 0 }

    // MARK: Telescope equipment

    /// Optics for the active scope + eyepiece under the current Bortle sky.
    var activeOptics: OpticsResult? { equipment.opticsResult(bortleClass: bortleClass) }

    // MARK: Favorites

    var favoriteObjects: [any CelestialObject] { favorites.objects(in: catalog) }

    // MARK: Selection & navigation

    /// Object currently shown in the info card / detail sheet.
    var selectedObjectID: String?
    /// Object the AR view should guide the user toward.
    var guideTargetID: String?
    /// Requests the Sky tab to become active (used by "Find in AR").
    var skyTabRequested = false

    /// Manual fine-alignment of the AR sky overlay about the zenith axis,
    /// in radians. Set by a two-finger horizontal drag in AR mode; lives here
    /// so it survives tab switches and AR-view rebuilds.
    var skyAlignmentOffset: Float = 0 {
        didSet { UserDefaults.standard.set(Double(skyAlignmentOffset), forKey: "skyAlignmentOffset") }
    }
    var hasAlignmentOffset: Bool { abs(skyAlignmentOffset) > 0.0001 }
    func resetAlignment() { skyAlignmentOffset = 0 }

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

    /// Naked-eye limiting magnitude implied by the Bortle class
    /// (Bortle 1 → 7.5, Bortle 9 → 4.0, linear between).
    var bortleLimitingMagnitude: Double {
        7.5 - Double(bortleClass - 1) * (7.5 - 4.0) / 8.0
    }

    /// The magnitude limit actually used for rendering: the user's slider,
    /// capped by what the Bortle sky can show.
    var effectiveMagnitudeLimit: Double {
        min(magnitudeLimit, bortleLimitingMagnitude)
    }

    // MARK: Satellite favorites & pass notifications

    func toggleFavoriteSatellite(_ id: String) {
        favorites.toggleSatellite(id)
        Task { await refreshPassNotifications() }
    }

    /// Recompute upcoming visible passes for favorited satellites and schedule
    /// (or clear) their pre-pass notifications.
    func refreshPassNotifications() async {
        guard passNotificationsEnabled, !favorites.satelliteIDs.isEmpty else {
            notificationScheduler.cancelAll()
            return
        }
        let observer = observer
        let favs = favorites.satelliteIDs.compactMap { satelliteService.satellite(withID: $0) }
        let passes = await Task.detached(priority: .utility) {
            favs.flatMap {
                $0.passes(observer: observer, startingAt: Date(), hours: 24)
            }.filter(\.isVisible)
        }.value
        await notificationScheduler.reschedule(passes: passes)
    }

    /// Fetch upcoming sky events for the next 30 days and schedule (or clear)
    /// their evening-before notifications.
    func refreshEventNotifications() async {
        guard eventNotificationsEnabled else {
            await eventNotificationScheduler.cancelAll()
            return
        }
        let observer = observer
        let start = Date()
        let events = await Task.detached(priority: .utility) {
            EventsEngine.upcoming(observer: observer, startingAt: start, days: 30)
        }.value
        await eventNotificationScheduler.reschedule(events: events)
    }

    // MARK: Lifecycle

    func start() {
        // On first launch, onboarding requests location in context (page 2);
        // afterwards request it up front.
        if hasOnboarded { locationService.requestLocation() }
        Task {
            await upgradeToDeepCatalog()
            await satelliteService.start()
            await refreshPassNotifications()
            await refreshEventNotifications()
        }
    }

    /// Loads the HYG deep-star catalog off the main actor and swaps it in.
    /// No-op when hygdata.csv is not bundled.
    private func upgradeToDeepCatalog() async {
        let deepStars = await Task.detached(priority: .utility) {
            HYGCatalogLoader.loadIfAvailable()
        }.value
        if let stars = deepStars {
            catalog = SkyCatalog(deepStars: stars)
        }
    }
}
