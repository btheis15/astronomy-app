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

    let catalog = SkyCatalog()
    let satelliteService = SatelliteService()
    let locationService = LocationService()
    let notificationScheduler = PassNotificationScheduler()
    private var _equipment: EquipmentLibrary?

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
            if clamped != bortleClass { bortleClass = clamped }
            UserDefaults.standard.set(bortleClass, forKey: "bortleClass")
        }
    }

    var magnitudeLimit: Double = 5.5 {
        didSet { UserDefaults.standard.set(magnitudeLimit, forKey: "magnitudeLimit") }
    }

    var passNotificationsEnabled: Bool = false {
        didSet { UserDefaults.standard.set(passNotificationsEnabled, forKey: "passNotificationsEnabled") }
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

    var equipment: EquipmentLibrary {
        get {
            access(keyPath: \.equipment)
            if let cached = _equipment { return cached }
            guard let data = UserDefaults.standard.data(forKey: "equipmentLibrary"),
                  let library = try? JSONDecoder().decode(EquipmentLibrary.self, from: data) else {
                _equipment = .empty
                return .empty
            }
            _equipment = library
            return library
        }
        set {
            withMutation(keyPath: \.equipment) {
                _equipment = newValue
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
