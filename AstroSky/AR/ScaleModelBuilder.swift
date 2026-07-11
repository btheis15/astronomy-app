//
//  ScaleModelBuilder.swift
//  AstroSky
//
//  Builds a RealityKit entity tree for a Scale AR scene: the primary body at
//  the origin, satellites on scaled rings, floating name labels, and Saturn's
//  rings. Each body entity is named by its key for tap-to-identify.
//

import RealityKit
import UIKit
import simd

@MainActor
enum ScaleModelBuilder {
    /// Radius the primary body is drawn at (meters) — a ~30 cm model.
    static let primaryTargetMeters = 0.15

    static func build(scene: ScaleScene, distanceMode: DistanceMode) -> Entity {
        let bodies = ScaleModelCatalog.bodies(for: scene)
        let root = Entity()
        root.name = "scaleModelRoot"
        guard let primary = bodies.first else { return root }

        let scale = ScaleModelMath.sceneScale(primaryRadiusKm: primary.radiusKm,
                                              targetMeters: primaryTargetMeters)
        let primaryRadius = ScaleModelMath.bodyRadiusMeters(km: primary.radiusKm, scale: scale)
        root.addChild(makeBody(primary, radiusMeters: primaryRadius, position: .zero))

        let satellites = Array(bodies.dropFirst())
        for (index, body) in satellites.enumerated() {
            let radius = ScaleModelMath.bodyRadiusMeters(km: body.radiusKm, scale: scale)
            let distance = ScaleModelMath.distanceMeters(orbitKm: body.orbitRadiusKm ?? 0,
                                                         primaryRadiusMeters: primaryRadius,
                                                         scale: scale, mode: distanceMode,
                                                         satelliteIndex: index, satelliteCount: satellites.count)
            let angle = Double(index) / Double(max(1, satellites.count)) * 2 * .pi + 0.3
            let position = SIMD3<Float>(Float(cos(angle) * distance), 0, Float(sin(angle) * distance))
            root.addChild(makeBody(body, radiusMeters: radius, position: position))
        }
        return root
    }

    private static func makeBody(_ body: ScaleBody, radiusMeters: Double, position: SIMD3<Float>) -> Entity {
        let holder = Entity()
        holder.name = body.key
        holder.position = position

        let radius = Float(radiusMeters)
        let mesh = MeshResource.generateSphere(radius: radius)
        let material = bodyMaterial(for: body)
        let sphere = ModelEntity(mesh: mesh, materials: [material])
        sphere.name = body.key
        sphere.generateCollisionShapes(recursive: false)   // enables arView.entity(at:)
        holder.addChild(sphere)

        if body.hasRings {
            holder.addChild(makeRing(innerRadius: radius * 1.2, outerRadius: radius * 2.3))
        }

        // Floating name label just above the body.
        let label = SkySceneBuilder.makeLabel(text: body.name, color: .white,
                                              size: CGFloat(max(0.02, radiusMeters * 0.9)))
        label.position = SIMD3(0, radius + Float(max(0.03, radiusMeters * 0.8)), 0)
        holder.addChild(label)
        return holder
    }

    private static func bodyMaterial(for body: ScaleBody) -> Material {
        let texture = ScaleModelTexture.texture(for: body)
        if body.key == "sun" || body.key == "milkyway" {
            // Self-luminous — no scene lighting needed.
            var unlit = UnlitMaterial(color: UIColor(red: body.tint.x, green: body.tint.y, blue: body.tint.z, alpha: 1))
            if let texture { unlit.color = .init(tint: .white, texture: .init(texture)) }
            return unlit
        }
        var material = PhysicallyBasedMaterial()
        if let texture {
            material.baseColor = .init(tint: .white, texture: .init(texture))
        } else {
            material.baseColor = .init(tint: UIColor(red: body.tint.x, green: body.tint.y, blue: body.tint.z, alpha: 1))
        }
        material.roughness = 0.9
        material.metallic = 0.0
        return material
    }

    private static func makeRing(innerRadius: Float, outerRadius: Float) -> ModelEntity {
        var vertices: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        let segments = 64
        for i in 0...segments {
            let a = Float(i) / Float(segments) * 2 * .pi
            let c = cos(a), s = sin(a)
            let v = Float(i) / Float(segments)
            vertices.append(SIMD3(innerRadius * c, 0, innerRadius * s)); uvs.append(SIMD2(0, v))
            vertices.append(SIMD3(outerRadius * c, 0, outerRadius * s)); uvs.append(SIMD2(1, v))
        }
        for i in 0..<segments {
            let b = UInt32(i * 2)
            indices.append(contentsOf: [b, b + 1, b + 2, b + 1, b + 3, b + 2,
                                        b, b + 2, b + 1, b + 1, b + 2, b + 3])
        }
        let mesh = SkySceneBuilder.makeMesh(name: "saturnRing", vertices: vertices, indices: indices, uvs: uvs)
            ?? MeshResource.generateBox(size: 0.001)
        var material: Material
        if let ring = ScaleModelTexture.ringTexture() {
            var pbr = UnlitMaterial(color: .white)
            pbr.color = .init(tint: .white, texture: .init(ring))
            pbr.blending = .transparent(opacity: .init(floatLiteral: 1.0))
            material = pbr
        } else {
            var tan = UnlitMaterial(color: UIColor(red: 0.85, green: 0.75, blue: 0.55, alpha: 1))
            tan.blending = .transparent(opacity: .init(floatLiteral: 0.6))
            material = tan
        }
        return ModelEntity(mesh: mesh, materials: [material])
    }
}
