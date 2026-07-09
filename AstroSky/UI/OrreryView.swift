//
//  OrreryView.swift
//  AstroSky
//
//  A Sun-centered 3D orrery: a non-AR RealityKit scene showing the planets on
//  their orbits with log-scaled distances, a date scrubber sharing the app's
//  time-travel offset, and drag/pinch camera control.
//

import RealityKit
import SwiftUI

struct OrreryView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        ZStack(alignment: .bottom) {
            OrrerySceneView(julianDate: appState.skyJulianDate)
                .ignoresSafeArea()

            VStack(spacing: 8) {
                if !appState.isLiveTime {
                    Text(appState.skyDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.footnote.monospacedDigit().weight(.medium))
                }
                HStack {
                    Text("−1y").font(.caption2)
                    Slider(value: $appState.timeOffset, in: -365 * 86_400...365 * 86_400, step: 86_400)
                    Text("+1y").font(.caption2)
                }
                Button("Today") { appState.resetToLiveTime() }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding()
        }
        .navigationTitle("Orrery")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct OrrerySceneView: UIViewRepresentable {
    let julianDate: Double

    func makeCoordinator() -> OrreryScene { OrreryScene() }

    func makeUIView(context: Context) -> ARView {
        context.coordinator.makeView()
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.update(julianDate: julianDate)
    }
}

@MainActor
final class OrreryScene: NSObject {
    private let arView = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
    private let root = AnchorEntity(world: .zero)
    private let camera = PerspectiveCamera()
    private var planetEntities: [Planet: Entity] = [:]

    private var cameraYaw: Float = 0.6
    private var cameraPitch: Float = 0.9
    private var cameraDistance: Float = 26

    /// Scene radius for an orbital distance (AU), log-scaled so the inner
    /// planets aren't cramped and Neptune still fits.
    private func sceneRadius(au: Double) -> Float { Float(log10(au + 1.0)) * 6.0 }

    func makeView() -> ARView {
        arView.environment.background = .color(.black)
        arView.scene.addAnchor(root)

        // Sun.
        let sun = ModelEntity(mesh: .generateSphere(radius: 0.9),
                              materials: [UnlitMaterial(color: UIColor(red: 1, green: 0.86, blue: 0.4, alpha: 1))])
        root.addChild(sun)

        // Orbit rings + planet markers.
        for planet in Planet.allCases where planet != .earth || true {
            let a = semiMajorAU(planet)
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

    private func semiMajorAU(_ planet: Planet) -> Double {
        switch planet {
        case .mercury: 0.387
        case .venus: 0.723
        case .earth: 1.0
        case .mars: 1.524
        case .jupiter: 5.203
        case .saturn: 9.537
        case .uranus: 19.19
        case .neptune: 30.07
        }
    }

    private func markerRadius(_ planet: Planet) -> Float {
        switch planet {
        case .jupiter, .saturn: 0.5
        case .uranus, .neptune: 0.4
        default: 0.28
        }
    }
}
