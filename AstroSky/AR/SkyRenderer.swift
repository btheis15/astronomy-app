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
    private let constellationLines: Entity
    private let constellationLabels: Entity
    private let starLabels: Entity
    private let deepSkyMarkers: Entity
    private let solarSystemRoot: Entity
    private let solarSystemMarkers: [String: Entity]
    private let horizon: Entity
    private let selectionHighlight: Entity
    private var satelliteEntities: [String: Entity] = [:]
    private let satelliteRoot = Entity()

    // Update bookkeeping.
    private var updateTimer: Timer?
    private var sceneSubscription: Cancellable?
    private var lastSolarUpdateJD: Double = 0
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
        self.lastMagnitudeLimit = appState.magnitudeLimit

        let arSupported = ARWorldTrackingConfiguration.isSupported
        self.isARMode = arSupported && !preferManualMode

        arView = ARView(frame: .zero,
                        cameraMode: isARMode ? .ar : .nonAR,
                        automaticallyConfigureSession: false)
        arView.renderOptions.insert([.disableMotionBlur, .disableDepthOfField])

        // Build the static scene once.
        starField = SkySceneBuilder.buildStarField(stars: appState.catalog.stars,
                                                   magnitudeLimit: appState.magnitudeLimit)
        constellationLines = SkySceneBuilder.buildConstellationLines()
        constellationLabels = SkySceneBuilder.buildConstellationLabels()
        starLabels = SkySceneBuilder.buildStarLabels(stars: appState.catalog.stars)
        deepSkyMarkers = SkySceneBuilder.buildDeepSkyMarkers()
        let solar = SkySceneBuilder.buildSolarSystemMarkers()
        solarSystemRoot = solar.root
        solarSystemMarkers = solar.markers
        horizon = SkySceneBuilder.buildHorizon()
        selectionHighlight = SkySceneBuilder.buildSelectionHighlight()

        super.init()

        skyRoot.addChild(starField)
        skyRoot.addChild(constellationLines)
        skyRoot.addChild(constellationLabels)
        skyRoot.addChild(starLabels)
        skyRoot.addChild(deepSkyMarkers)
        skyRoot.addChild(solarSystemRoot)
        worldAnchor.addChild(skyRoot)
        worldAnchor.addChild(horizon)
        worldAnchor.addChild(satelliteRoot)
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

        // Sidereal rotation of the whole sky.
        skyRoot.orientation = SkySceneBuilder.skyOrientation(julianDate: jd, observer: observer)

        // Settings.
        constellationLines.isEnabled = appState.showConstellationLines
        constellationLabels.isEnabled = appState.showConstellationLines && appState.showLabels
        starLabels.isEnabled = appState.showLabels
        deepSkyMarkers.isEnabled = appState.showDeepSky
        satelliteRoot.isEnabled = appState.showSatellites

        if appState.magnitudeLimit != lastMagnitudeLimit {
            lastMagnitudeLimit = appState.magnitudeLimit
            rebuildStarField()
        }

        // Solar system moves slowly; recompute every 30 sky-seconds.
        if abs(jd - lastSolarUpdateJD) * 86_400 > 30 {
            lastSolarUpdateJD = jd
            updateSolarSystem(julianDate: jd)
        }

        updateSatellites(julianDate: jd, observer: observer)
        updateSelectionHighlight(julianDate: jd, observer: observer)
    }

    private func rebuildStarField() {
        starField.removeFromParent()
        starField = SkySceneBuilder.buildStarField(stars: appState.catalog.stars,
                                                   magnitudeLimit: appState.magnitudeLimit)
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
        let maxAngle = 5.0 * AstroMath.degToRad

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
        for star in appState.catalog.stars where star.visualMagnitude <= appState.magnitudeLimit {
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

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        manualFOV = min(max(manualFOV / Float(gesture.scale), 20), 90)
        gesture.scale = 1
        manualCamera.camera.fieldOfViewInDegrees = manualFOV
    }

    private func applyManualCameraOrientation() {
        let yawRotation = simd_quatf(angle: manualYaw, axis: SIMD3(0, 1, 0))
        let pitchRotation = simd_quatf(angle: manualPitch, axis: SIMD3(1, 0, 0))
        manualCamera.orientation = yawRotation * pitchRotation
    }
}
