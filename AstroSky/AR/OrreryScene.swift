//
//  OrreryScene.swift
//  AstroSky
//
//  RealityKit coordinator for the orrery. Orbit rings and planet markers are
//  log-scaled so the inner planets aren't cramped and Neptune still fits.
//

import RealityKit
import UIKit

@MainActor
final class OrreryScene: NSObject {
    private let arView = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
    private let root = AnchorEntity(world: .zero)
    private let camera = PerspectiveCamera()
    private var planetEntities: [Planet: Entity] = [:]

    private var cameraYaw: Float = 0.6
    private var cameraPitch: Float = 0.9
    private var cameraDistance: Float = 26

    /// Log-scaled scene radius for a given orbital distance in AU.
    private func sceneRadius(au: Double) -> Float { Float(log10(au + 1.0)) * 6.0 }

    func makeView() -> ARView {
        arView.environment.background = .color(.black)
        arView.scene.addAnchor(root)

        // Sun.
        let sun = ModelEntity(mesh: .generateSphere(radius: 0.9),
                              materials: [UnlitMaterial(color: UIColor(red: 1, green: 0.86, blue: 0.4, alpha: 1))])
        root.addChild(sun)

        // Orbit rings + planet markers.
        for planet in Planet.allCases where planet != .earth {
            let a = planet.semiMajorAxisAU
            root.addChild(makeOrbitRing(radius: sceneRadius(au: a)))
            let marker = ModelEntity(mesh: .generateSphere(radius: markerRadius(planet)),
                                     materials: [UnlitMaterial(color: SkySceneBuilder.planetColor(planet))])
            planetEntities[planet] = marker
            root.addChild(marker)
        }

        let cameraAnchor = AnchorEntity(world: .zero)
        cameraAnchor.addChild(camera)
        arView.scene.addAnchor(cameraAnchor)
        applyCamera()

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        arView.addGestureRecognizer(pan)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        arView.addGestureRecognizer(pinch)
        return arView
    }

    func update(julianDate jd: Double) {
        for (planet, entity) in planetEntities {
            let helio = PlanetEphemeris.heliocentricPosition(of: planet, julianDate: jd)
            let auRadius = (helio.x * helio.x + helio.y * helio.y).squareRoot()
            let angle = atan2(helio.y, helio.x)
            let r = sceneRadius(au: auRadius)
            entity.position = SIMD3(r * Float(cos(angle)), 0, r * Float(sin(angle)))
        }
    }

    // MARK: Camera

    private func applyCamera() {
        let x = cameraDistance * cos(cameraPitch) * sin(cameraYaw)
        let y = cameraDistance * sin(cameraPitch)
        let z = cameraDistance * cos(cameraPitch) * cos(cameraYaw)
        camera.position = SIMD3(x, y, z)
        camera.look(at: .zero, from: camera.position, relativeTo: nil)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let t = gesture.translation(in: arView)
        gesture.setTranslation(.zero, in: arView)
        cameraYaw -= Float(t.x) * 0.01
        cameraPitch = min(max(cameraPitch - Float(t.y) * 0.01, 0.15), 1.5)
        applyCamera()
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        cameraDistance = min(max(cameraDistance / Float(gesture.scale), 8), 60)
        gesture.scale = 1
        applyCamera()
    }

    // MARK: Helpers

    private func makeOrbitRing(radius: Float) -> Entity {
        var vertices: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        let segments = 96
        for i in 0..<segments {
            let a0 = Float(i) / Float(segments) * 2 * .pi
            let a1 = Float(i + 1) / Float(segments) * 2 * .pi
            let p0 = SIMD3(radius * cos(a0), 0, radius * sin(a0))
            let p1 = SIMD3(radius * cos(a1), 0, radius * sin(a1))
            SkySceneBuilder.appendSegment(from: p0, to: p1, width: 0.03,
                                          vertices: &vertices, indices: &indices)
        }
        let entity = Entity()
        if let mesh = SkySceneBuilder.makeMesh(name: "orbit", vertices: vertices, indices: indices) {
            var material = UnlitMaterial(color: UIColor(white: 0.5, alpha: 1))
            material.blending = .transparent(opacity: .init(floatLiteral: 0.35))
            entity.addChild(ModelEntity(mesh: mesh, materials: [material]))
        }
        return entity
    }

    private func markerRadius(_ planet: Planet) -> Float {
        switch planet {
        case .jupiter, .saturn: 0.5
        case .uranus, .neptune: 0.4
        default: 0.28
        }
    }
}
