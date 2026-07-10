//
//  SkyRenderer.swift
//  AstroSky
//
//  Owns the ARView and the celestial scene, and keeps them in sync with
//  time, location, settings and live satellite data.
//
//  Two display modes share the same scene:
//  • AR mode — camera passthrough, `.gravityAndHeading` world alignment,
//    so scene axes are geographically aligned (x=east, y=up, z=south).
//  • Manual mode — `.nonAR` camera on a black sky, driven by drag/pinch.
//    Used in Simulator, on devices without AR support, or by user choice.
//

import ARKit
import Combine
import Foundation
import RealityKit
import UIKit
import simd

/// What the on-screen guidance arrow should show for a "Find in AR" target.
struct GuideReadout: Equatable {
    var targetName: String
    /// Angle of the direction arrow in screen space, radians
    /// (0 = right, π/2 = up).
    var arrowAngle: Double
    /// True when the target is inside the current field of view.
    var isOnTarget: Bool
    /// True when the target is below the horizon.
    var isBelowHorizon: Bool
}

@MainActor
final class SkyRenderer: NSObject {
    let arView: ARView
    let isARMode: Bool
    private unowned let appState: AppState

    var onGuideUpdate: ((GuideReadout?) -> Void)?

    // Scene graph.
    private let worldAnchor = AnchorEntity(world: matrix_identity_float4x4)
    private let skyRoot = Entity()
    private var starField: Entity
    private let milkyWay: Entity
    private let constellationLines: Entity
    private let constellationLabels: Entity
    private let celestialEquator: Entity
    private let ecliptic: Entity
    private let coordinateGrid: Entity
    private let starLabels: Entity
    private let starLabelTiers: [(entity: Entity, magnitude: Double)]
    private let deepSkyMarkers: Entity
    private let messierSecondaryLabels: [Entity]
    private let solarSystemRoot: Entity
    private let solarSystemMarkers: [String: Entity]
    private let horizon: Entity
    private let selectionHighlight: Entity
    private var satelliteEntities: [String: Entity] = [:]
    private let satelliteRoot = Entity()
    private var satelliteTrack = Entity()
    private var meteorRadiants = Entity()
    private var lastActiveShowers: Set<String> = []
    private var lastShowerDay = Int.min
    private let horizonGlow: Entity

    // Update bookkeeping.
    private var updateTimer: Timer?
    private var sceneSubscription: Cancellable?
    private var lastSolarUpdateJD: Double = 0
    private var lastTrackID: String?
    private var lastTrackJD: Double = 0
    private var lastMagnitudeLimit: Double
    private var lastGuideNotify = Date.distantPast
    private var lastGuideReadout: GuideReadout?

    // Manual-mode camera state.
    private let manualCamera = PerspectiveCamera()
    private var manualYaw: Float = .pi          // facing south
    private var manualPitch: Float = 0.35
    private var manualFOV: Float = 60

    // MARK: Setup

    init(appState: AppState, preferManualMode: Bool) {
        self.appState = appState
        self.lastMagnitudeLimit = appState.effectiveMagnitudeLimit

        let arSupported = ARWorldTrackingConfiguration.isSupported
        self.isARMode = arSupported && !preferManualMode

        arView = ARView(frame: .zero,
                        cameraMode: isARMode ? .ar : .nonAR,
                        automaticallyConfigureSession: false)
        arView.renderOptions.insert([.disableMotionBlur, .disableDepthOfField])

        // Build the static scene once.
        starField = SkySceneBuilder.buildStarField(stars: appState.catalog.stars,
                                                   magnitudeLimit: appState.effectiveMagnitudeLimit)
        milkyWay = SkySceneBuilder.buildMilkyWay()
        constellationLines = SkySceneBuilder.buildConstellationLines()
        constellationLabels = SkySceneBuilder.buildConstellationLabels()
        celestialEquator = SkySceneBuilder.buildCelestialEquator()
        ecliptic = SkySceneBuilder.buildEcliptic()
        coordinateGrid = SkySceneBuilder.buildCoordinateGrid()
        let builtStarLabels = SkySceneBuilder.buildStarLabels(stars: appState.catalog.stars)
        starLabels = builtStarLabels.root
        starLabelTiers = builtStarLabels.tiers
        let builtDeepSky = SkySceneBuilder.buildDeepSkyMarkers()
        deepSkyMarkers = builtDeepSky.root
        messierSecondaryLabels = builtDeepSky.secondaryLabels
        let solar = SkySceneBuilder.buildSolarSystemMarkers()
        solarSystemRoot = solar.root
        solarSystemMarkers = solar.markers
        horizon = SkySceneBuilder.buildHorizon()
        horizonGlow = SkySceneBuilder.buildHorizonGlow()
        selectionHighlight = SkySceneBuilder.buildSelectionHighlight()

        super.init()

        skyRoot.addChild(milkyWay)
        skyRoot.addChild(starField)
        skyRoot.addChild(coordinateGrid)
        skyRoot.addChild(celestialEquator)
        skyRoot.addChild(ecliptic)
        skyRoot.addChild(constellationLines)
        skyRoot.addChild(constellationLabels)
        skyRoot.addChild(starLabels)
        skyRoot.addChild(deepSkyMarkers)
        skyRoot.addChild(meteorRadiants)
        skyRoot.addChild(solarSystemRoot)
        worldAnchor.addChild(skyRoot)
        worldAnchor.addChild(horizonGlow)
        worldAnchor.addChild(horizon)
        worldAnchor.addChild(satelliteRoot)
        worldAnchor.addChild(satelliteTrack)
        worldAnchor.addChild(selectionHighlight)
        arView.scene.addAnchor(worldAnchor)

        if isARMode {
            let configuration = ARWorldTrackingConfiguration()
            configuration.worldAlignment = .gravityAndHeading
            configuration.planeDetection = []
            arView.session.run(configuration)
        } else {
            arView.environment.background = .color(.black)
            manualCamera.camera.fieldOfViewInDegrees = manualFOV
            let cameraAnchor = AnchorEntity(world: matrix_identity_float4x4)
            cameraAnchor.addChild(manualCamera)
            arView.scene.addAnchor(cameraAnchor)
            applyManualCameraOrientation()
            installManualGestures()
        }

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        arView.addGestureRecognizer(tap)

        // AR fine-alignment: a two-finger horizontal drag rotates the overlay
        // about the zenith to correct heading error. (Manual mode uses one- and
        // two-finger drags for looking around, so this is AR-only.)
        if isARMode {
            let alignPan = UIPanGestureRecognizer(target: self, action: #selector(handleAlignPan(_:)))
            alignPan.minimumNumberOfTouches = 2
            alignPan.maximumNumberOfTouches = 2
            arView.addGestureRecognizer(alignPan)
        }

        // Per-frame camera tracking for the guidance arrow (throttled).
        sceneSubscription = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateGuideIfNeeded()
            }
        }

        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        updateTimer = timer

        tick()

        // Overlay real-photo sprites on deep-sky showpieces, loaded lazily after
        // the scene's first paint so startup stays snappy.
        Task { @MainActor [weak self] in await self?.loadDeepSkySprites() }
    }

    /// Attach real-photo sprites for the brightest deep-sky objects that have a
    /// bundled image, yielding between each so the frame never stalls.
    private func loadDeepSkySprites() async {
        let showpieces = appState.catalog.deepSky
            .filter { ObjectImagery.hasImage(for: $0) && $0.visualMagnitude <= 9.0 }
            .sorted { $0.visualMagnitude < $1.visualMagnitude }
            .prefix(30)
        for object in showpieces {
            let direction = SkySceneBuilder.equatorialVector(object.equatorialJ2000)
            let size = AngularSizeSource.angularSizeRadians(for: object, julianDate: 2_451_545.0)
            guard let cg = ObjectImagery.thumbnailCGImage(deepSkyID: object.id, maxPixel: 256),
                  let texture = try? await TextureResource(image: cg, withName: "sprite_\(object.id)",
                                                           options: .init(semantic: .color)) else {
                await Task.yield()
                continue
            }
            let sprite = SkySceneBuilder.makeDeepSkySprite(texture: texture, direction: direction,
                                                           angularSizeRadians: size)
            sprite.name = "sprite.\(object.id)"
            deepSkyMarkers.addChild(sprite)
            // Hide the small ring glyph now that the photo stands in for it.
            deepSkyMarkers.children.first { $0.name == object.id }?.isEnabled = false
            await Task.yield()
        }
    }

    /// Capture the current sky view (camera feed + overlay in AR mode) and
    /// composite a small "AstroSky · date · place" caption onto it.
    func captureSnapshot() async -> UIImage? {
        let base: UIImage? = await withCheckedContinuation { continuation in
            arView.snapshot(saveToHDR: false) { image in
                continuation.resume(returning: image)
            }
        }
        guard let base else { return nil }

        let place = appState.locationService.placeName
            ?? String(format: "%.1f°, %.1f°", appState.observer.latitudeDegrees, appState.observer.longitudeDegrees)
        let dateText = appState.skyDate.formatted(date: .abbreviated, time: .shortened)
        let caption = "AstroSky · \(dateText) · \(place)"

        let renderer = UIGraphicsImageRenderer(size: base.size)
        return renderer.image { context in
            base.draw(at: .zero)
            let fontSize = max(14, base.size.width * 0.028)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: UIColor.white,
            ]
            let textSize = (caption as NSString).size(withAttributes: attributes)
            let margin = fontSize
            let box = CGRect(x: margin, y: base.size.height - textSize.height - margin * 1.6,
                             width: textSize.width + fontSize, height: textSize.height + fontSize * 0.6)
            let pill = UIBezierPath(roundedRect: box, cornerRadius: box.height / 2)
            UIColor.black.withAlphaComponent(0.45).setFill()
            pill.fill()
            (caption as NSString).draw(at: CGPoint(x: box.minX + fontSize / 2, y: box.minY + fontSize * 0.3),
                                       withAttributes: attributes)
        }
    }

    func tearDown() {
        updateTimer?.invalidate()
        updateTimer = nil
        sceneSubscription?.cancel()
        if isARMode {
            arView.session.pause()
        }
    }

    // MARK: Periodic update

    private func tick() {
        let jd = appState.skyJulianDate
        let observer = appState.observer

        // Sidereal rotation of the whole sky, with the manual fine-alignment
        // offset applied about the zenith (scene +Y) on top of it.
        let baseOrientation = SkySceneBuilder.skyOrientation(julianDate: jd, observer: observer)
        let alignment = simd_quatf(angle: appState.skyAlignmentOffset, axis: SIMD3(0, 1, 0))
        skyRoot.orientation = alignment * baseOrientation

        // Settings.
        constellationLines.isEnabled = appState.showConstellationLines
        celestialEquator.isEnabled = appState.showCelestialEquator
        ecliptic.isEnabled = appState.showEcliptic
        coordinateGrid.isEnabled = appState.showCoordinateGrid

        // Milky Way: on/off, and dim with the magnitude-limit slider (a lower
        // limit ≈ more light pollution ⇒ a fainter band).
        milkyWay.isEnabled = appState.showMilkyWay
        if appState.showMilkyWay {
            let t = (appState.magnitudeLimit - 2.0) / (6.5 - 2.0)
            let opacity = Float(0.2 + 0.8 * min(1, max(0, t)))
            milkyWay.components.set(OpacityComponent(opacity: opacity))
        }
        deepSkyMarkers.isEnabled = appState.showDeepSky
        satelliteRoot.isEnabled = appState.showSatellites
        updateLabelDensity()

        // Meteor-shower radiants change at most daily — only recompute the
        // active set when the (sky) day rolls over, not every tick.
        if appState.showMeteorShowers {
            let day = Int(appState.skyDate.timeIntervalSince1970 / 86_400)
            if day != lastShowerDay {
                lastShowerDay = day
                let active = Set(MeteorShowers.active(on: appState.skyDate).map(\.name))
                if active != lastActiveShowers {
                    lastActiveShowers = active
                    rebuildMeteorRadiants()
                }
            }
        }
        meteorRadiants.isEnabled = appState.showMeteorShowers

        if appState.effectiveMagnitudeLimit != lastMagnitudeLimit {
            lastMagnitudeLimit = appState.effectiveMagnitudeLimit
            rebuildStarField()
        }

        // Horizon light-pollution glow scales with the Bortle class
        // (Bortle 1 ≈ none, Bortle 9 ≈ strong wash-out near the horizon).
        let glowStrength = Float(appState.bortleClass - 1) / 8.0
        horizonGlow.isEnabled = glowStrength > 0.01
        horizonGlow.components.set(OpacityComponent(opacity: glowStrength))

        // Solar system moves slowly; recompute every 30 sky-seconds.
        if abs(jd - lastSolarUpdateJD) * 86_400 > 30 {
            lastSolarUpdateJD = jd
            updateSolarSystem(julianDate: jd)
        }

        updateSatellites(julianDate: jd, observer: observer)
        updateSatelliteTrack(julianDate: jd, observer: observer)
        updateSelectionHighlight(julianDate: jd, observer: observer)
    }

    /// Effective vertical field of view in degrees. Manual mode tracks the
    /// pinch-zoom FOV; AR mode is roughly fixed, so it uses a nominal value.
    private var currentFOV: Float { isARMode ? 60 : manualFOV }

    /// Reveal or hide labels by density as the view zooms: at a narrow FOV
    /// (zoomed in) show fainter star labels and every Messier designation; at
    /// a wide FOV show only the brightest star labels and constellation names.
    private func updateLabelDensity() {
        let fov = currentFOV
        // Star-label magnitude cutoff: 3.5 at ≤40°, 1.5 at ≥60°, lerp between.
        let cutoff: Double
        if fov <= 40 { cutoff = 3.5 }
        else if fov >= 60 { cutoff = 1.5 }
        else { cutoff = 3.5 - Double((fov - 40) / 20) * (3.5 - 1.5) }

        starLabels.isEnabled = appState.showLabels
        if appState.showLabels {
            for tier in starLabelTiers {
                tier.entity.isEnabled = tier.magnitude <= cutoff
            }
        }

        // Constellation names: only at a wide-enough FOV (they clutter a
        // zoomed-in view where individual star labels take over).
        constellationLabels.isEnabled =
            appState.showConstellationLines && appState.showLabels && fov >= 45

        // Full Messier designations only when zoomed in.
        let showAllMessier = appState.showDeepSky && appState.showLabels && fov <= 40
        for label in messierSecondaryLabels {
            label.isEnabled = showAllMessier
        }
    }

    private func rebuildMeteorRadiants() {
        meteorRadiants.removeFromParent()
        meteorRadiants = SkySceneBuilder.buildMeteorRadiants(MeteorShowers.active(on: appState.skyDate))
        skyRoot.addChild(meteorRadiants)
    }

    private func rebuildStarField() {
        starField.removeFromParent()
        starField = SkySceneBuilder.buildStarField(stars: appState.catalog.stars,
                                                   magnitudeLimit: appState.effectiveMagnitudeLimit)
        skyRoot.addChild(starField)
    }

    private func updateSolarSystem(julianDate jd: Double) {
        let radius = SkySceneBuilder.sphereRadius * 0.98
        var positions: [String: EquatorialCoordinates] = [:]
        positions["sun"] = SunObject().skyPosition(julianDate: jd, observer: appState.observer).equatorialJ2000
        positions["moon"] = MoonObject().skyPosition(julianDate: jd, observer: appState.observer).equatorialJ2000
        for planet in Planet.visible {
            positions["planet.\(planet.rawValue)"] =
                PlanetEphemeris.position(of: planet, julianDate: jd).equatorialJ2000
        }
        for body in MinorBodyEphemeris.bodies {
            positions["minor.\(body.key)"] =
                MinorBodyEphemeris.state(body, julianDate: jd).equatorialJ2000
        }
        for (id, eq) in positions {
            guard let marker = solarSystemMarkers[id] else { continue }
            let direction = SkySceneBuilder.equatorialVector(eq)
            marker.position = direction * radius
            SkySceneBuilder.orientTowardCenter(marker, at: marker.position)
        }
    }

    private func updateSatellites(julianDate jd: Double, observer: Observer) {
        guard appState.showSatellites else { return }

        var displaySet = appState.satelliteService.featured
        if appState.showStarlink {
            displaySet.append(contentsOf: appState.satelliteService.starlinkForDisplay)
        }

        var liveIDs = Set<String>()
        let radius = SkySceneBuilder.sphereRadius * 0.9

        for satellite in displaySet {
            liveIDs.insert(satellite.id)
            let entity: Entity
            if let existing = satelliteEntities[satellite.id] {
                entity = existing
            } else {
                let labeled = !satellite.isStarlink
                entity = SkySceneBuilder.makeSatelliteMarker(isStarlink: satellite.isStarlink,
                                                             name: labeled ? satellite.name : nil)
                entity.name = satellite.id
                satelliteEntities[satellite.id] = entity
                satelliteRoot.addChild(entity)
            }

            if let observation = satellite.observe(julianDate: jd, observer: observer),
               observation.horizontal.altitude > -0.01 {
                let direction = SkySceneBuilder.sceneDirection(horizontal: observation.horizontal)
                entity.position = direction * radius
                SkySceneBuilder.orientTowardCenter(entity, at: entity.position,
                                                   referenceUp: SIMD3(0, 1, 0))
                entity.isEnabled = true
            } else {
                entity.isEnabled = false
            }
        }

        // Drop entities for satellites no longer displayed.
        for (id, entity) in satelliteEntities where !liveIDs.contains(id) {
            entity.removeFromParent()
            satelliteEntities.removeValue(forKey: id)
        }
    }

    /// Draw a ±10-minute predicted sky track for the selected satellite,
    /// sampled every 15 s (world frame). Rebuilt each tick so it follows both
    /// the satellite's motion and any time-travel change.
    private func updateSatelliteTrack(julianDate jd: Double, observer: Observer) {
        let satellite = appState.showSatellites ? appState.selectedObject as? Satellite : nil

        // Nothing selected: clear an existing track once, then stay idle.
        guard let satellite else {
            if lastTrackID != nil {
                satelliteTrack.removeFromParent()
                satelliteTrack = Entity()
                worldAnchor.addChild(satelliteTrack)
                lastTrackID = nil
            }
            return
        }

        // The ground track is 81 SGP4 samples + a polyline mesh — only rebuild
        // when the selection changes or time has moved enough to matter.
        if satellite.id == lastTrackID && abs(jd - lastTrackJD) * 86_400 < 5 { return }
        lastTrackID = satellite.id
        lastTrackJD = jd

        satelliteTrack.removeFromParent()
        satelliteTrack = Entity()
        worldAnchor.addChild(satelliteTrack)

        let radius = SkySceneBuilder.sphereRadius * 0.9
        let points: [SIMD3<Float>?] = stride(from: -600.0, through: 600.0, by: 15.0).map { offset in
            let sampleJD = jd + offset / 86_400.0
            guard let observation = satellite.observe(julianDate: sampleJD, observer: observer),
                  observation.horizontal.altitude > -0.05 else { return nil }
            return SkySceneBuilder.sceneDirection(horizontal: observation.horizontal) * radius
        }

        let color = satellite.isStarlink
            ? UIColor(white: 0.8, alpha: 1)
            : UIColor(red: 0.55, green: 1.0, blue: 0.75, alpha: 1)
        let track = SkySceneBuilder.buildSatelliteTrack(points: points, color: color)
        satelliteTrack.addChild(track)
    }

    private func updateSelectionHighlight(julianDate jd: Double, observer: Observer) {
        guard let selected = appState.selectedObject else {
            selectionHighlight.isEnabled = false
            return
        }
        guard let direction = worldDirection(of: selected, julianDate: jd, observer: observer) else {
            selectionHighlight.isEnabled = false
            return
        }
        selectionHighlight.isEnabled = true
        selectionHighlight.position = direction * (SkySceneBuilder.sphereRadius * 0.88)
    }

    /// World-frame unit direction toward an object.
    func worldDirection(of object: any CelestialObject,
                        julianDate jd: Double,
                        observer: Observer) -> SIMD3<Float>? {
        let position = object.skyPosition(julianDate: jd, observer: observer)
        return SkySceneBuilder.sceneDirection(horizontal: position.horizontal)
    }

    // MARK: Guidance arrow

    private func updateGuideIfNeeded() {
        guard Date().timeIntervalSince(lastGuideNotify) > 0.1 else { return }
        lastGuideNotify = Date()

        guard let target = appState.guideTarget else {
            if lastGuideReadout != nil {
                lastGuideReadout = nil
                onGuideUpdate?(nil)
            }
            return
        }
        let jd = appState.skyJulianDate
        let position = target.skyPosition(julianDate: jd, observer: appState.observer)
        let targetDirection = SkySceneBuilder.sceneDirection(horizontal: position.horizontal)

        let cameraTransform = arView.cameraTransform
        let rotation = cameraTransform.rotation
        let forward = rotation.act(SIMD3<Float>(0, 0, -1))
        let right = rotation.act(SIMD3<Float>(1, 0, 0))
        let up = rotation.act(SIMD3<Float>(0, 1, 0))

        let dx = simd_dot(targetDirection, right)
        let dy = simd_dot(targetDirection, up)
        let dz = simd_dot(targetDirection, forward)

        let onTarget = dz > cos(12 * Float(AstroMath.degToRad))
        let readout = GuideReadout(targetName: target.name,
                                   arrowAngle: Double(atan2(dy, dx)),
                                   isOnTarget: onTarget,
                                   isBelowHorizon: !position.horizontal.isAboveHorizon)
        guard readout != lastGuideReadout else { return }
        lastGuideReadout = readout
        onGuideUpdate?(readout)
    }

    // MARK: Tap to identify

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: arView)
        guard let ray = arView.ray(through: point) else { return }
        let tapDirection = simd_normalize(ray.direction)

        if let object = identifyObject(along: tapDirection) {
            appState.select(object)
        } else {
            appState.select(nil)
        }
    }

    /// Find the celestial object nearest to a world-space direction.
    /// Brighter objects get a small angular "gravity" so that tapping near
    /// Jupiter picks Jupiter, not a 5th-magnitude star beside it.
    func identifyObject(along direction: SIMD3<Float>) -> (any CelestialObject)? {
        let jd = appState.skyJulianDate
        let observer = appState.observer
        // Forgiving, zoom-aware catch radius: a constant ~13% of the field of
        // view (with a generous floor) so tapping near an object selects it,
        // even on a wide field where a fixed 5° felt tiny on screen.
        let maxAngle = max(7.0, Double(currentFOV) * 0.13) * AstroMath.degToRad

        var best: (object: any CelestialObject, score: Double)?

        func consider(_ object: any CelestialObject, worldDirection: SIMD3<Float>) {
            let dot = simd_dot(direction, worldDirection)
            let angle = Double(acos(min(1, max(-1, dot))))
            guard angle < maxAngle else { return }
            let magnitude = object.magnitude ?? 3.0
            let weight = 1.0 + max(0, min(magnitude, 6.5)) * 0.25
            let score = angle * weight
            if best == nil || score < best!.score {
                best = (object, score)
            }
        }

        // Solar system + satellites: use live scene positions.
        var solarObjects: [any CelestialObject] = [appState.catalog.sun, appState.catalog.moon]
        solarObjects.append(contentsOf: appState.catalog.planets.map { $0 as any CelestialObject })
        solarObjects.append(contentsOf: appState.catalog.minorBodies.map { $0 as any CelestialObject })
        for object in solarObjects {
            if let dir = worldDirection(of: object, julianDate: jd, observer: observer),
               object.horizontal(julianDate: jd, observer: observer).altitude > -0.05 {
                consider(object, worldDirection: dir)
            }
        }

        if appState.showSatellites {
            var candidates = appState.satelliteService.featured
            if appState.showStarlink {
                candidates.append(contentsOf: appState.satelliteService.starlinkForDisplay)
            }
            for satellite in candidates {
                guard let entity = satelliteEntities[satellite.id], entity.isEnabled else { continue }
                consider(satellite, worldDirection: simd_normalize(entity.position))
            }
        }

        // Stars & deep sky: rotate catalog vectors by the current sky
        // orientation instead of walking entities.
        let orientation = skyRoot.orientation
        for star in appState.catalog.stars where star.visualMagnitude <= appState.effectiveMagnitudeLimit {
            let world = orientation.act(SkySceneBuilder.equatorialVector(star.equatorialJ2000))
            consider(star, worldDirection: world)
        }
        if appState.showDeepSky {
            for object in appState.catalog.deepSky
            where object.visualMagnitude <= SkySceneBuilder.deepSkyMagnitudeCut {
                let world = orientation.act(SkySceneBuilder.equatorialVector(object.equatorialJ2000))
                consider(object, worldDirection: world)
            }
        }

        return best?.object
    }

    // MARK: Manual-mode camera

    private func installManualGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        arView.addGestureRecognizer(pan)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        arView.addGestureRecognizer(pinch)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: arView)
        gesture.setTranslation(.zero, in: arView)
        let radiansPerPoint = Float(manualFOV * Float(AstroMath.degToRad)) / Float(max(arView.bounds.height, 1))
        manualYaw += Float(translation.x) * radiansPerPoint
        manualPitch += Float(translation.y) * radiansPerPoint
        manualPitch = min(max(manualPitch, -.pi / 2), .pi / 2)
        applyManualCameraOrientation()
    }

    @objc private func handleAlignPan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: arView)
        gesture.setTranslation(.zero, in: arView)
        // Map a full screen-width drag to roughly the horizontal field of view.
        let radiansPerPoint = Float(60 * AstroMath.degToRad) / Float(max(arView.bounds.width, 1))
        appState.skyAlignmentOffset += Float(translation.x) * radiansPerPoint
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        manualFOV = min(max(manualFOV / Float(gesture.scale), 20), 90)
        gesture.scale = 1
        manualCamera.camera.fieldOfViewInDegrees = manualFOV
        updateLabelDensity()
    }

    private func applyManualCameraOrientation() {
        let yawRotation = simd_quatf(angle: manualYaw, axis: SIMD3(0, 1, 0))
        let pitchRotation = simd_quatf(angle: manualPitch, axis: SIMD3(1, 0, 0))
        manualCamera.orientation = yawRotation * pitchRotation
    }
}
