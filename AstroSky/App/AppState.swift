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
    let notificationScheduler = PassNotificationScheduler()

    var observer: Observer { locationService.observer }

    // MARK: Time travel

    /// Offset applied to the wall clock, seconds. 0 = live sky.
    var timeOffset: TimeInterval = 0
    var isLiveTime: Bool { abs(timeOffset) < 1 }

    /// The instant the sky is being rendered for.
    var skyDate: Date { Date().addingTimeInterval(timeOffset) }
    var skyJulianDate: Double { AstroTime.julianDate(skyDate) }

    func resetToLiveTime() { timeOffset = 0 }

    // MARK: Telescope equipment

    var equipment: EquipmentLibrary {
        get {
            access(keyPath: \.equipment)
            guard let data = UserDefaults.standard.data(forKey: "equipmentLibrary"),
                  let library = try? JSONDecoder().decode(EquipmentLibrary.self, from: data) else {
                return .empty
            }
            return library
        }
        set {
            withMutation(keyPath: \.equipment) {
                if let data = try? JSONEncoder().encode(newValue) {
                    UserDefaults.standard.set(data, forKey: "equipmentLibrary")
                }
            }
        }
    }

    /// Optics for the active scope + eyepiece under the current Bortle sky.
    var activeOptics: OpticsResult? { equipment.opticsResult(bortleClass: bortleClass) }

    func addTelescope(_ scope: Telescope) {
        var library = equipment
        library.telescopes.append(scope)
        if library.activeTelescopeID == nil { library.activeTelescopeID = scope.id }
        equipment = library
    }

    func addEyepiece(_ eyepiece: Eyepiece) {
        var library = equipment
        library.eyepieces.append(eyepiece)
        if library.activeEyepieceID == nil { library.activeEyepieceID = eyepiece.id }
        equipment = library
    }

    func deleteTelescope(_ id: UUID) {
        var library = equipment
        library.telescopes.removeAll { $0.id == id }
        if library.activeTelescopeID == id { library.activeTelescopeID = library.telescopes.first?.id }
        equipment = library
    }

    func deleteEyepiece(_ id: UUID) {
        var library = equipment
        library.eyepieces.removeAll { $0.id == id }
        if library.activeEyepieceID == id { library.activeEyepieceID = library.eyepieces.first?.id }
        equipment = library
    }

    func setActiveTelescope(_ id: UUID) { var l = equipment; l.activeTelescopeID = id; equipment = l }
    func setActiveEyepiece(_ id: UUID) { var l = equipment; l.activeEyepieceID = id; equipment = l }
    func setMountType(_ mount: MountType) { var l = equipment; l.mountType = mount; equipment = l }

    // MARK: Favorites (any object)

    var favoriteObjectIDs: Set<String> {
        get {
            access(keyPath: \.favoriteObjectIDs)
            return Set(UserDefaults.standard.stringArray(forKey: "favoriteObjectIDs") ?? [])
        }
        set {
            withMutation(keyPath: \.favoriteObjectIDs) {
                UserDefaults.standard.set(Array(newValue), forKey: "favoriteObjectIDs")
            }
        }
    }

    func isFavorite(_ id: String) -> Bool { favoriteObjectIDs.contains(id) }

    func toggleFavorite(_ id: String) {
        var favorites = favoriteObjectIDs
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
        favoriteObjectIDs = favorites
    }

    var favoriteObjects: [any CelestialObject] {
        favoriteObjectIDs.sorted().compactMap { object(withID: $0) }
    }

    // MARK: Onboarding

    /// True once the first-launch onboarding flow has been completed or skipped.
    var hasOnboarded: Bool {
        get { access(keyPath: \.hasOnboarded); return defaults(bool: "hasOnboarded", default: false) }
        set { withMutation(keyPath: \.hasOnboarded) { UserDefaults.standard.set(newValue, forKey: "hasOnboarded") } }
    }

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
    var skyAlignmentOffset: Float = 0
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

    var showMeteorShowers: Bool {
        get { access(keyPath: \.showMeteorShowers); return defaults(bool: "showMeteorShowers", default: true) }
        set { withMutation(keyPath: \.showMeteorShowers) { UserDefaults.standard.set(newValue, forKey: "showMeteorShowers") } }
    }

    var showMilkyWay: Bool {
        get { access(keyPath: \.showMilkyWay); return defaults(bool: "showMilkyWay", default: true) }
        set { withMutation(keyPath: \.showMilkyWay) { UserDefaults.standard.set(newValue, forKey: "showMilkyWay") } }
    }

    /// Reference overlays drawn in the equatorial mesh frame.
    var showEcliptic: Bool {
        get { access(keyPath: \.showEcliptic); return defaults(bool: "showEcliptic", default: false) }
        set { withMutation(keyPath: \.showEcliptic) { UserDefaults.standard.set(newValue, forKey: "showEcliptic") } }
    }

    var showCelestialEquator: Bool {
        get { access(keyPath: \.showCelestialEquator); return defaults(bool: "showCelestialEquator", default: false) }
        set { withMutation(keyPath: \.showCelestialEquator) { UserDefaults.standard.set(newValue, forKey: "showCelestialEquator") } }
    }

    var showCoordinateGrid: Bool {
        get { access(keyPath: \.showCoordinateGrid); return defaults(bool: "showCoordinateGrid", default: false) }
        set { withMutation(keyPath: \.showCoordinateGrid) { UserDefaults.standard.set(newValue, forKey: "showCoordinateGrid") } }
    }

    /// Bortle dark-sky class (1 = pristine … 9 = inner city). Caps how faint
    /// the naked-eye sky gets and drives horizon light-pollution glow.
    var bortleClass: Int {
        get {
            access(keyPath: \.bortleClass)
            let stored = UserDefaults.standard.integer(forKey: "bortleClass")
            return stored == 0 ? 4 : min(9, max(1, stored))
        }
        set { withMutation(keyPath: \.bortleClass) { UserDefaults.standard.set(min(9, max(1, newValue)), forKey: "bortleClass") } }
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

    // MARK: Satellite favorites & pass notifications

    var favoriteSatelliteIDs: Set<String> {
        get {
            access(keyPath: \.favoriteSatelliteIDs)
            let stored = UserDefaults.standard.stringArray(forKey: "favoriteSatelliteIDs") ?? []
            return Set(stored)
        }
        set {
            withMutation(keyPath: \.favoriteSatelliteIDs) {
                UserDefaults.standard.set(Array(newValue), forKey: "favoriteSatelliteIDs")
            }
        }
    }

    func isFavoriteSatellite(_ id: String) -> Bool { favoriteSatelliteIDs.contains(id) }

    func toggleFavoriteSatellite(_ id: String) {
        var favorites = favoriteSatelliteIDs
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
        favoriteSatelliteIDs = favorites
        Task { await refreshPassNotifications() }
    }

    var passNotificationsEnabled: Bool {
        get { access(keyPath: \.passNotificationsEnabled); return defaults(bool: "passNotificationsEnabled", default: false) }
        set { withMutation(keyPath: \.passNotificationsEnabled) { UserDefaults.standard.set(newValue, forKey: "passNotificationsEnabled") } }
    }

    /// Recompute upcoming visible passes for favorited satellites and schedule
    /// (or clear) their pre-pass notifications.
    func refreshPassNotifications() async {
        guard passNotificationsEnabled, !favoriteSatelliteIDs.isEmpty else {
            notificationScheduler.cancelAll()
            return
        }
        let observer = observer
        let favorites = favoriteSatelliteIDs.compactMap { satelliteService.satellite(withID: $0) }
        let passes = await Task.detached(priority: .utility) {
            favorites.flatMap {
                $0.passes(observer: observer, startingAt: Date(), hours: 24)
            }.filter(\.isVisible)
        }.value
        await notificationScheduler.reschedule(passes: passes)
    }

    // MARK: Lifecycle

    func start() {
        // On first launch, onboarding requests location in context (page 2);
        // afterwards request it up front.
        if hasOnboarded { locationService.requestLocation() }
        Task {
            await satelliteService.start()
            await refreshPassNotifications()
        }
    }
}
