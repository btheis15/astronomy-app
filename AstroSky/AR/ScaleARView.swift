//
//  ScaleARView.swift
//  AstroSky
//
//  Hosts the Scale AR scene: tap a detected surface to place the model, pinch
//  to resize, drag to rotate, tap a body to learn about it. On Simulator (no
//  AR) it falls back to a floating model with an orbit/pinch camera.
//

import ARKit
import RealityKit
import SwiftUI
import simd

struct ScaleARView: UIViewRepresentable {
    let scene: ScaleScene
    let distanceMode: DistanceMode
    /// Height of the model above the placed surface, in meters (AR only).
    var heightMeters: Float = 0
    var onSelect: (ScaleBody) -> Void
    var onPlacementChange: (Bool) -> Void

    func makeCoordinator() -> ScaleARScene {
        ScaleARScene(onSelect: onSelect, onPlacementChange: onPlacementChange)
    }

    func makeUIView(context: Context) -> ARView {
        context.coordinator.makeView(scene: scene, distanceMode: distanceMode)
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.update(scene: scene, distanceMode: distanceMode)
        context.coordinator.setHeight(heightMeters)
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: ScaleARScene) {
        coordinator.tearDown()
    }
}

@MainActor
final class ScaleARScene: NSObject {
    private let arView: ARView
    private let isAR: Bool
    private let onSelect: (ScaleBody) -> Void
    private let onPlacementChange: (Bool) -> Void

    private var placementAnchor: AnchorEntity?
    private let modelHolder = Entity()
    private var scene: ScaleScene = .earthMoon
    private var distanceMode: DistanceMode = .fit
    private var isPlaced = false
    private var currentScale: Float = 1
    private var heightMeters: Float = 0

    // Non-AR camera.
    private let camera = PerspectiveCamera()
    private var camYaw: Float = 0.5
    private var camPitch: Float = 0.4
    private var camDistance: Float = 1.2

    init(onSelect: @escaping (ScaleBody) -> Void, onPlacementChange: @escaping (Bool) -> Void) {
        self.onSelect = onSelect
        self.onPlacementChange = onPlacementChange
        self.isAR = ARWorldTrackingConfiguration.isSupported
        arView = ARView(frame: .zero, cameraMode: isAR ? .ar : .nonAR,
                        automaticallyConfigureSession: false)
        super.init()
    }

    func makeView(scene: ScaleScene, distanceMode: DistanceMode) -> ARView {
        self.scene = scene
        self.distanceMode = distanceMode

        if isAR {
            let config = ARWorldTrackingConfiguration()
            config.planeDetection = [.horizontal]
            arView.session.run(config)
        } else {
            arView.environment.background = .color(.black)
            let camAnchor = AnchorEntity(world: .zero)
            camAnchor.addChild(camera)
            arView.scene.addAnchor(camAnchor)
            applyCamera()
            // Float the model in front immediately.
            let anchor = AnchorEntity(world: .zero)
            anchor.addChild(modelHolder)
            arView.scene.addAnchor(anchor)
            placementAnchor = anchor
            isPlaced = true
            rebuildModel()
            onPlacementChange(true)
        }

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        arView.addGestureRecognizer(tap)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        arView.addGestureRecognizer(pinch)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        arView.addGestureRecognizer(pan)
        return arView
    }

    func update(scene: ScaleScene, distanceMode: DistanceMode) {
        let changed = scene != self.scene || distanceMode != self.distanceMode
        self.scene = scene
        self.distanceMode = distanceMode
        if changed && isPlaced { rebuildModel() }
    }

    /// Raise the placed model above its surface (AR only) so it's comfortable to
    /// view standing up outdoors, not just on a table.
    func setHeight(_ height: Float) {
        heightMeters = height
        if isAR && isPlaced { modelHolder.position = SIMD3(0, height, 0) }
    }

    func tearDown() {
        if isAR { arView.session.pause() }
    }

    // MARK: Model

    private func rebuildModel() {
        modelHolder.children.forEach { $0.removeFromParent() }
        modelHolder.addChild(ScaleModelBuilder.build(scene: scene, distanceMode: distanceMode))
    }

    // MARK: Gestures

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: arView)

        // Place on first tap in AR.
        if isAR && !isPlaced {
            guard let result = arView.raycast(from: point, allowing: .estimatedPlane, alignment: .horizontal).first
            else { return }
            let anchor = AnchorEntity(world: result.worldTransform)
            anchor.addChild(modelHolder)
            arView.scene.addAnchor(anchor)
            placementAnchor = anchor
            isPlaced = true
            modelHolder.position = SIMD3(0, heightMeters, 0)
            rebuildModel()
            onPlacementChange(true)
            return
        }

        // Otherwise, tap a body to select it.
        if let entity = arView.entity(at: point),
           let body = ScaleModelCatalog.bodies(for: scene).first(where: { $0.key == entity.name }) {
            onSelect(body)
        }
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard isPlaced else { return }
        if isAR {
            currentScale = min(max(currentScale * Float(gesture.scale), 0.15), 6)
            modelHolder.scale = SIMD3(repeating: currentScale)
        } else {
            camDistance = min(max(camDistance / Float(gesture.scale), 0.4), 4)
            applyCamera()
        }
        gesture.scale = 1
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard isPlaced else { return }
        let t = gesture.translation(in: arView)
        gesture.setTranslation(.zero, in: arView)
        if isAR {
            modelHolder.orientation *= simd_quatf(angle: Float(t.x) * 0.01, axis: SIMD3(0, 1, 0))
        } else {
            camYaw -= Float(t.x) * 0.01
            camPitch = min(max(camPitch - Float(t.y) * 0.01, -1.4), 1.4)
            applyCamera()
        }
    }

    private func applyCamera() {
        let x = camDistance * cos(camPitch) * sin(camYaw)
        let y = camDistance * sin(camPitch)
        let z = camDistance * cos(camPitch) * cos(camYaw)
        camera.position = SIMD3(x, y, z)
        camera.look(at: .zero, from: camera.position, relativeTo: nil)
    }
}
