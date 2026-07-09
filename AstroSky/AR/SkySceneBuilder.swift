//
//  SkySceneBuilder.swift
//  AstroSky
//
//  Builds the RealityKit entities of the celestial scene.
//
//  Geometry strategy: the star field and constellation figures are built
//  ONCE in the J2000 equatorial frame as a handful of batched meshes
//  (thousands of stars → a few draw calls), all parented to a single
//  "sky root" entity. Sidereal motion, the observer's latitude and
//  precession are then just one quaternion on that root, updated once a
//  second by SkyRenderer.
//
//  Scene frame (matches ARKit's .gravityAndHeading alignment):
//  +X = east, +Y = up, +Z = south.
//

import Foundation
import RealityKit
import UIKit
import simd

enum SkySceneBuilder {
    /// Radius of the celestial sphere in scene meters. Far enough that
    /// parallax from walking around is negligible, near enough to avoid
    /// depth-buffer trouble.
    static let sphereRadius: Float = 100

    // MARK: Coordinate helpers

    /// Unit vector in the equatorial mesh frame for J2000 coordinates.
    static func equatorialVector(_ eq: EquatorialCoordinates) -> SIMD3<Float> {
        let v = eq.unitVector
        return SIMD3(Float(v.x), Float(v.y), Float(v.z))
    }

    /// Scene-frame direction for horizontal coordinates:
    /// x = east, y = up, z = −north.
    static func sceneDirection(horizontal h: HorizontalCoordinates) -> SIMD3<Float> {
        let cosAlt = cos(h.altitude)
        let east = cosAlt * sin(h.azimuth)
        let north = cosAlt * cos(h.azimuth)
        let up = sin(h.altitude)
        return SIMD3(Float(east), Float(up), Float(-north))
    }

    /// Rotation taking J2000 equatorial mesh coordinates into the scene
    /// frame for a given time and latitude (includes precession).
    static func skyOrientation(julianDate jd: Double, observer: Observer) -> simd_quatf {
        let lst = AstroTime.localMeanSiderealTime(julianDate: jd, longitude: observer.longitude)
        let lat = observer.latitude
        let sinL = sin(lst), cosL = cos(lst)
        let sinP = sin(lat), cosP = cos(lat)

        // Equatorial (of date) → East/North/Up.
        let m = simd_double3x3(rows: [
            SIMD3(-sinL, cosL, 0),                    // E
            SIMD3(-sinP * cosL, -sinP * sinL, cosP),  // N
            SIMD3(cosP * cosL, cosP * sinL, sinP),    // U
        ])
        // ENU → scene (x=E, y=U, z=−N).
        let a = simd_double3x3(rows: [
            SIMD3(1, 0, 0),
            SIMD3(0, 0, 1),
            SIMD3(0, -1, 0),
        ])
        // J2000 → of date.
        let p = CoordinateTransforms.precessionMatrixFromJ2000(julianDate: jd)

        let r = a * m * p
        let rf = simd_float3x3(columns: (SIMD3<Float>(rf: r.columns.0),
                                         SIMD3<Float>(rf: r.columns.1),
                                         SIMD3<Float>(rf: r.columns.2)))
        return simd_quatf(rf)
    }

    // MARK: Star field

    /// Star color from the B−V index, bucketed for batching.
    static func colorBucket(forColorIndex bv: Double) -> Int {
        switch bv {
        case ..<0.0: 0
        case ..<0.3: 1
        case ..<0.6: 2
        case ..<0.85: 3
        case ..<1.4: 4
        default: 5
        }
    }

    static let bucketColors: [UIColor] = [
        UIColor(red: 0.68, green: 0.79, blue: 1.00, alpha: 1),  // blue
        UIColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1),  // white
        UIColor(red: 1.00, green: 0.98, blue: 0.88, alpha: 1),  // yellow-white
        UIColor(red: 1.00, green: 0.94, blue: 0.76, alpha: 1),  // yellow
        UIColor(red: 1.00, green: 0.84, blue: 0.62, alpha: 1),  // orange
        UIColor(red: 1.00, green: 0.72, blue: 0.52, alpha: 1),  // red-orange
    ]

    /// Apparent quad half-size in meters for a magnitude, at sphereRadius.
    static func starSize(magnitude: Double) -> Float {
        let size = 0.95 * pow(0.80, magnitude)
        return Float(min(1.8, max(0.16, size)))
    }

    /// Build the batched star-field entity (one child per color bucket).
    static func buildStarField(stars: [Star], magnitudeLimit: Double) -> Entity {
        let root = Entity()
        root.name = "starField"

        var bucketVertices: [[SIMD3<Float>]] = Array(repeating: [], count: bucketColors.count)
        var bucketIndices: [[UInt32]] = Array(repeating: [], count: bucketColors.count)

        for star in stars where star.visualMagnitude <= magnitudeLimit {
            let bucket = colorBucket(forColorIndex: star.colorIndex)
            let direction = equatorialVector(star.equatorialJ2000)
            appendQuad(center: direction * sphereRadius,
                       radialDirection: direction,
                       halfSize: starSize(magnitude: star.visualMagnitude),
                       vertices: &bucketVertices[bucket],
                       indices: &bucketIndices[bucket])
        }

        for bucket in bucketColors.indices where !bucketVertices[bucket].isEmpty {
            if let mesh = makeMesh(name: "stars\(bucket)",
                                   vertices: bucketVertices[bucket],
                                   indices: bucketIndices[bucket]) {
                let material = UnlitMaterial(color: bucketColors[bucket])
                let entity = ModelEntity(mesh: mesh, materials: [material])
                root.addChild(entity)
            }
        }
        return root
    }

    // MARK: Constellation figures

    static func buildConstellationLines() -> Entity {
        var vertices: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        for constellation in ConstellationCatalog.constellations {
            for (a, b) in constellation.starPairs {
                appendGreatCircleSegment(from: equatorialVector(a.equatorialJ2000),
                                         to: equatorialVector(b.equatorialJ2000),
                                         width: 0.14,
                                         vertices: &vertices,
                                         indices: &indices)
            }
        }

        let root = Entity()
        root.name = "constellationLines"
        if let mesh = makeMesh(name: "constellations", vertices: vertices, indices: indices) {
            var material = UnlitMaterial(color: UIColor(red: 0.45, green: 0.62, blue: 0.90, alpha: 1))
            material.blending = .transparent(opacity: .init(floatLiteral: 0.42))
            root.addChild(ModelEntity(mesh: mesh, materials: [material]))
        }
        return root
    }

    /// Constellation name labels at figure centers.
    static func buildConstellationLabels() -> Entity {
        let root = Entity()
        root.name = "constellationLabels"
        for constellation in ConstellationCatalog.constellations {
            guard let center = constellation.centerJ2000 else { continue }
            let direction = equatorialVector(center)
            let label = makeLabel(text: constellation.name.uppercased(),
                                  color: UIColor(red: 0.55, green: 0.68, blue: 0.95, alpha: 1),
                                  size: 1.9)
            place(label: label, at: direction * (sphereRadius * 0.995))
            root.addChild(label)
        }
        return root
    }

    /// Labels for named bright stars (down to a magnitude cut).
    static func buildStarLabels(stars: [Star], magnitudeCut: Double = 2.2) -> Entity {
        let root = Entity()
        root.name = "starLabels"
        for star in stars where star.visualMagnitude <= magnitudeCut && star.properName != nil {
            let direction = equatorialVector(star.equatorialJ2000)
            let label = makeLabel(text: star.name,
                                  color: UIColor(white: 0.9, alpha: 1),
                                  size: 1.5)
            // Offset the label slightly below the star.
            place(label: label, at: direction * sphereRadius, verticalOffset: -1.6)
            root.addChild(label)
        }
        return root
    }

    // MARK: Deep-sky markers

    static let deepSkyMagnitudeCut = 9.0

    static func deepSkyColor(for type: DeepSkyType) -> UIColor {
        switch type {
        case .galaxy: UIColor(red: 0.98, green: 0.80, blue: 0.90, alpha: 1)
        case .globularCluster, .openCluster: UIColor(red: 0.95, green: 0.92, blue: 0.60, alpha: 1)
        case .nebula, .planetaryNebula, .supernovaRemnant: UIColor(red: 0.55, green: 0.92, blue: 0.88, alpha: 1)
        case .starCloud, .asterism: UIColor(red: 0.85, green: 0.85, blue: 0.95, alpha: 1)
        }
    }

    /// Ring-style markers for Messier objects, with labels for named ones.
    static func buildDeepSkyMarkers() -> Entity {
        let root = Entity()
        root.name = "deepSky"
        for object in MessierCatalog.objects where object.visualMagnitude <= deepSkyMagnitudeCut {
            let direction = equatorialVector(object.equatorialJ2000)
            let color = deepSkyColor(for: object.type)

            var vertices: [SIMD3<Float>] = []
            var indices: [UInt32] = []
            appendRing(center: direction * sphereRadius,
                       radialDirection: direction,
                       radius: 0.9,
                       width: 0.14,
                       vertices: &vertices,
                       indices: &indices)
            if let mesh = makeMesh(name: object.id, vertices: vertices, indices: indices) {
                var material = UnlitMaterial(color: color)
                material.blending = .transparent(opacity: .init(floatLiteral: 0.8))
                let marker = ModelEntity(mesh: mesh, materials: [material])
                marker.name = object.id
                root.addChild(marker)
            }

            if object.commonName != nil || object.visualMagnitude <= 6.5 {
                let label = makeLabel(text: object.designation, color: color.withAlphaComponent(0.9), size: 1.2)
                place(label: label, at: direction * sphereRadius, verticalOffset: -1.8)
                root.addChild(label)
            }
        }
        return root
    }

    // MARK: Solar system markers

    static func planetColor(_ planet: Planet) -> UIColor {
        switch planet {
        case .mercury: UIColor(red: 0.75, green: 0.72, blue: 0.68, alpha: 1)
        case .venus: UIColor(red: 1.00, green: 0.96, blue: 0.82, alpha: 1)
        case .earth: UIColor.systemBlue
        case .mars: UIColor(red: 1.00, green: 0.55, blue: 0.35, alpha: 1)
        case .jupiter: UIColor(red: 0.93, green: 0.83, blue: 0.68, alpha: 1)
        case .saturn: UIColor(red: 0.95, green: 0.88, blue: 0.65, alpha: 1)
        case .uranus: UIColor(red: 0.65, green: 0.90, blue: 0.94, alpha: 1)
        case .neptune: UIColor(red: 0.45, green: 0.62, blue: 0.98, alpha: 1)
        }
    }

    static func planetMarkerRadius(_ planet: Planet) -> Float {
        switch planet {
        case .venus, .jupiter: 1.15
        case .saturn: 1.05
        case .mars: 0.95
        case .mercury: 0.75
        default: 0.7
        }
    }

    /// Sun, Moon and planet marker entities, keyed by object ID. Positions
    /// are set by SkyRenderer each update tick (children of the sky root,
    /// equatorial frame).
    static func buildSolarSystemMarkers() -> (root: Entity, markers: [String: Entity]) {
        let root = Entity()
        root.name = "solarSystem"
        var markers: [String: Entity] = [:]

        func addMarker(id: String, labelText: String, color: UIColor, radius: Float) {
            let holder = Entity()
            holder.name = id
            let sphere = ModelEntity(mesh: .generateSphere(radius: radius),
                                     materials: [UnlitMaterial(color: color)])
            holder.addChild(sphere)
            let label = makeLabel(text: labelText, color: color, size: 1.7)
            label.position = SIMD3(0, -radius - 1.7, 0)
            holder.addChild(label)
            markers[id] = holder
            root.addChild(holder)
        }

        addMarker(id: "sun", labelText: "Sun",
                  color: UIColor(red: 1.0, green: 0.93, blue: 0.55, alpha: 1), radius: 2.3)
        addMarker(id: "moon", labelText: "Moon",
                  color: UIColor(white: 0.92, alpha: 1), radius: 2.1)
        for planet in Planet.visible {
            addMarker(id: "planet.\(planet.rawValue)", labelText: planet.name,
                      color: planetColor(planet), radius: planetMarkerRadius(planet))
        }
        return (root, markers)
    }

    // MARK: Horizon & compass

    /// Horizon ring with cardinal-direction labels (fixed world frame).
    static func buildHorizon() -> Entity {
        let root = Entity()
        root.name = "horizon"

        var vertices: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        let radius: Float = sphereRadius * 0.96
        let segments = 96
        for i in 0..<segments {
            let a0 = Float(i) / Float(segments) * 2 * .pi
            let a1 = Float(i + 1) / Float(segments) * 2 * .pi
            let p0 = SIMD3(radius * sin(a0), 0, -radius * cos(a0))
            let p1 = SIMD3(radius * sin(a1), 0, -radius * cos(a1))
            appendSegment(from: p0, to: p1, width: 0.12, vertices: &vertices, indices: &indices)
        }
        if let mesh = makeMesh(name: "horizonRing", vertices: vertices, indices: indices) {
            var material = UnlitMaterial(color: UIColor(red: 0.9, green: 0.45, blue: 0.30, alpha: 1))
            material.blending = .transparent(opacity: .init(floatLiteral: 0.5))
            root.addChild(ModelEntity(mesh: mesh, materials: [material]))
        }

        let cardinals: [(String, Double)] = [("N", 0), ("NE", 45), ("E", 90), ("SE", 135),
                                             ("S", 180), ("SW", 225), ("W", 270), ("NW", 315)]
        for (text, azimuthDeg) in cardinals {
            let azimuth = azimuthDeg * AstroMath.degToRad
            let horizontal = HorizontalCoordinates(altitude: 2.0 * AstroMath.degToRad, azimuth: azimuth)
            let direction = sceneDirection(horizontal: horizontal)
            let isMajor = text.count == 1
            let label = makeLabel(text: text,
                                  color: UIColor(red: 0.95, green: 0.55, blue: 0.38, alpha: 1),
                                  size: isMajor ? 3.2 : 2.0)
            place(label: label, at: direction * radius, referenceUp: SIMD3(0, 1, 0))
            root.addChild(label)
        }
        return root
    }

    // MARK: Selection highlight

    static func buildSelectionHighlight() -> Entity {
        let holder = Entity()
        holder.name = "selectionHighlight"
        var material = UnlitMaterial(color: UIColor.systemYellow)
        material.blending = .transparent(opacity: .init(floatLiteral: 0.30))
        let sphere = ModelEntity(mesh: .generateSphere(radius: 2.6), materials: [material])
        holder.addChild(sphere)
        holder.isEnabled = false
        return holder
    }

    // MARK: Satellite markers

    static func makeSatelliteMarker(isStarlink: Bool, name: String?) -> Entity {
        let holder = Entity()
        let color = isStarlink
            ? UIColor(white: 0.75, alpha: 1)
            : UIColor(red: 0.55, green: 1.0, blue: 0.75, alpha: 1)
        let radius: Float = isStarlink ? 0.32 : 0.55
        let sphere = ModelEntity(mesh: .generateSphere(radius: radius),
                                 materials: [UnlitMaterial(color: color)])
        holder.addChild(sphere)
        if let name {
            let label = makeLabel(text: name, color: color, size: 1.3)
            label.position = SIMD3(0, -1.6, 0)
            holder.addChild(label)
        }
        return holder
    }

    // MARK: - Mesh primitives

    static func makeMesh(name: String, vertices: [SIMD3<Float>], indices: [UInt32]) -> MeshResource? {
        guard !vertices.isEmpty else { return nil }
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(vertices)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }

    /// Quad tangent to the sphere, facing the origin.
    static func appendQuad(center: SIMD3<Float>, radialDirection: SIMD3<Float>, halfSize: Float,
                           vertices: inout [SIMD3<Float>], indices: inout [UInt32]) {
        let reference: SIMD3<Float> = abs(radialDirection.z) > 0.98 ? SIMD3(1, 0, 0) : SIMD3(0, 0, 1)
        let t1 = simd_normalize(simd_cross(radialDirection, reference))
        let t2 = simd_normalize(simd_cross(radialDirection, t1))
        let base = UInt32(vertices.count)
        vertices.append(center - t1 * halfSize - t2 * halfSize)
        vertices.append(center + t1 * halfSize - t2 * halfSize)
        vertices.append(center + t1 * halfSize + t2 * halfSize)
        vertices.append(center - t1 * halfSize + t2 * halfSize)
        // Both windings so the quad is visible regardless of face culling.
        indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3,
                                    base, base + 2, base + 1, base, base + 3, base + 2])
    }

    /// Straight thin quad between two points (short segments only).
    static func appendSegment(from a: SIMD3<Float>, to b: SIMD3<Float>, width: Float,
                              vertices: inout [SIMD3<Float>], indices: inout [UInt32]) {
        let mid = (a + b) / 2
        let radial = simd_normalize(mid)
        let axis = simd_normalize(b - a)
        let side = simd_normalize(simd_cross(radial, axis)) * (width / 2)
        let base = UInt32(vertices.count)
        vertices.append(a - side)
        vertices.append(a + side)
        vertices.append(b + side)
        vertices.append(b - side)
        indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3,
                                    base, base + 2, base + 1, base, base + 3, base + 2])
    }

    /// Great-circle arc between two unit vectors, subdivided and slightly
    /// shortened at both ends so lines don't overlap the stars.
    static func appendGreatCircleSegment(from a: SIMD3<Float>, to b: SIMD3<Float>, width: Float,
                                         vertices: inout [SIMD3<Float>], indices: inout [UInt32]) {
        let angle = acos(min(1, max(-1, simd_dot(a, b))))
        guard angle > 0.001 else { return }
        let trim: Float = min(0.35, 0.012 / max(angle, 0.02))   // fraction to trim per end
        let steps = max(1, Int(angle / 0.05))                    // ~3° subdivisions
        var previous: SIMD3<Float>?
        for i in 0...steps {
            let t = trim + (1 - 2 * trim) * Float(i) / Float(steps)
            // Spherical linear interpolation between the two directions.
            let sinAngle = sin(angle)
            let w1 = sin((1 - t) * angle) / sinAngle
            let w2 = sin(t * angle) / sinAngle
            let point = simd_normalize(a * w1 + b * w2) * sphereRadius
            if let previous {
                appendSegment(from: previous, to: point, width: width,
                              vertices: &vertices, indices: &indices)
            }
            previous = point
        }
    }

    /// Flat ring (annulus) tangent to the sphere — used for deep-sky markers.
    static func appendRing(center: SIMD3<Float>, radialDirection: SIMD3<Float>,
                           radius: Float, width: Float,
                           vertices: inout [SIMD3<Float>], indices: inout [UInt32]) {
        let reference: SIMD3<Float> = abs(radialDirection.z) > 0.98 ? SIMD3(1, 0, 0) : SIMD3(0, 0, 1)
        let t1 = simd_normalize(simd_cross(radialDirection, reference))
        let t2 = simd_normalize(simd_cross(radialDirection, t1))
        let segments = 24
        for i in 0..<segments {
            let a0 = Float(i) / Float(segments) * 2 * .pi
            let a1 = Float(i + 1) / Float(segments) * 2 * .pi
            let p0 = center + (t1 * cos(a0) + t2 * sin(a0)) * radius
            let p1 = center + (t1 * cos(a1) + t2 * sin(a1)) * radius
            appendSegment(from: p0, to: p1, width: width, vertices: &vertices, indices: &indices)
        }
    }

    // MARK: Labels

    /// Billboard-ish text label: oriented to face the sphere center.
    static func makeLabel(text: String, color: UIColor, size: CGFloat) -> Entity {
        let mesh = MeshResource.generateText(text,
                                             extrusionDepth: 0.01,
                                             font: .systemFont(ofSize: size, weight: .medium),
                                             containerFrame: .zero,
                                             alignment: .center,
                                             lineBreakMode: .byWordWrapping)
        let material = UnlitMaterial(color: color)
        let model = ModelEntity(mesh: mesh, materials: [material])
        // Center the text mesh on its local origin.
        let bounds = mesh.bounds
        model.position = SIMD3(-bounds.center.x, -bounds.center.y, 0)
        let holder = Entity()
        holder.addChild(model)
        return holder
    }

    /// Orient an entity at `position` so its +Z (text front) faces the
    /// sphere center, with the given reference "up" direction kept upward.
    /// The default up is the equatorial mesh pole (+Z); pass `SIMD3(0,1,0)`
    /// for entities living in the world/scene frame.
    static func orientTowardCenter(_ entity: Entity,
                                   at position: SIMD3<Float>,
                                   referenceUp: SIMD3<Float> = SIMD3(0, 0, 1)) {
        let radial = simd_normalize(position)
        var up = referenceUp - radial * simd_dot(referenceUp, radial)
        if simd_length(up) < 0.05 {
            let fallback = SIMD3<Float>(0, 1, 0)
            up = fallback - radial * simd_dot(fallback, radial)
        }
        up = simd_normalize(up)
        let zAxis = -radial                       // text +Z faces the viewer
        let xAxis = simd_normalize(simd_cross(up, zAxis))
        let yAxis = simd_cross(zAxis, xAxis)
        entity.orientation = simd_quatf(simd_float3x3(columns: (xAxis, yAxis, zAxis)))
    }

    /// Position a label on the sphere and orient it toward the center.
    static func place(label: Entity, at position: SIMD3<Float>,
                      verticalOffset: Float = 0,
                      referenceUp: SIMD3<Float> = SIMD3(0, 0, 1)) {
        orientTowardCenter(label, at: position, referenceUp: referenceUp)
        let yAxis = label.orientation.act(SIMD3<Float>(0, 1, 0))
        label.position = position + yAxis * verticalOffset
    }
}

private extension SIMD3 where Scalar == Float {
    init(rf v: SIMD3<Double>) {
        self.init(Float(v.x), Float(v.y), Float(v.z))
    }
}
