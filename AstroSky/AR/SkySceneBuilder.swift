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

@MainActor
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

    /// Soft round glow sprite, generated once at runtime (white core →
    /// transparent edge). Tinted per color bucket by the material.
    static let glowTexture: TextureResource? = makeStarSprite(spikes: false)
    /// Variant with faint 4-point diffraction spikes for the brightest stars.
    static let spikeTexture: TextureResource? = makeStarSprite(spikes: true)

    /// Core Graphics radial-gradient sprite (optionally with diffraction
    /// spikes). RGB is white; the radial alpha falloff gives the round glow.
    private static func makeStarSprite(spikes: Bool) -> TextureResource? {
        let dimension = 128
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: dimension, height: dimension))
        let image = renderer.image { context in
            let cg = context.cgContext
            let center = CGPoint(x: dimension / 2, y: dimension / 2)
            let maxRadius = CGFloat(dimension) / 2
            let space = CGColorSpaceCreateDeviceRGB()
            guard let glow = CGGradient(colorsSpace: space,
                                        colors: [UIColor(white: 1, alpha: 1).cgColor,
                                                 UIColor(white: 1, alpha: 0).cgColor] as CFArray,
                                        locations: [0, 1]) else { return }
            cg.drawRadialGradient(glow, startCenter: center, startRadius: 0,
                                  endCenter: center, endRadius: maxRadius * 0.95, options: [])
            if spikes {
                cg.setBlendMode(.plusLighter)
                guard let spike = CGGradient(colorsSpace: space,
                                             colors: [UIColor(white: 1, alpha: 0.85).cgColor,
                                                      UIColor(white: 1, alpha: 0).cgColor] as CFArray,
                                             locations: [0, 1]) else { return }
                for angle in [0.0, Double.pi / 2] {
                    cg.saveGState()
                    cg.translateBy(x: center.x, y: center.y)
                    cg.rotate(by: CGFloat(angle))
                    cg.clip(to: CGRect(x: -maxRadius, y: -3, width: maxRadius * 2, height: 6))
                    cg.drawRadialGradient(spike, startCenter: .zero, startRadius: 0,
                                          endCenter: .zero, endRadius: maxRadius, options: [])
                    cg.restoreGState()
                }
            }
        }
        guard let cgImage = image.cgImage else { return nil }
        return try? TextureResource(image: cgImage, withName: spikes ? "starSpike" : "starGlow",
                                    options: .init(semantic: .color))
    }

    /// Unlit, additively-transparent material carrying a star sprite tinted to
    /// the bucket color; the sprite's alpha channel drives the soft edge.
    static func starMaterial(tint: UIColor, texture: TextureResource) -> UnlitMaterial {
        var material = UnlitMaterial(color: tint)
        material.color = .init(tint: tint, texture: .init(texture))
        material.blending = .transparent(opacity: .init(floatLiteral: 1.0))
        return material
    }

    /// Apparent quad half-size in meters for a magnitude, at sphereRadius.
    /// A steep falloff gives a strong, pro-app contrast between the few bright
    /// stars (large, glinting) and the faint background stars (small dots).
    static func starSize(magnitude: Double) -> Float {
        let size = 1.2 * pow(0.72, magnitude)
        return Float(min(2.8, max(0.12, size)))
    }

    /// Build the batched star-field entity: one textured child per color
    /// bucket for ordinary stars (soft round glow) and one per bucket for the
    /// brightest stars (mag < 0.5), which get the diffraction-spike sprite.
    static func buildStarField(stars: [Star], magnitudeLimit: Double) -> Entity {
        let root = Entity()
        root.name = "starField"

        let count = bucketColors.count
        var glowV = Array(repeating: [SIMD3<Float>](), count: count)
        var glowI = Array(repeating: [UInt32](), count: count)
        var glowUV = Array(repeating: [SIMD2<Float>](), count: count)
        var spikeV = Array(repeating: [SIMD3<Float>](), count: count)
        var spikeI = Array(repeating: [UInt32](), count: count)
        var spikeUV = Array(repeating: [SIMD2<Float>](), count: count)

        for star in stars where star.visualMagnitude <= magnitudeLimit {
            let bucket = colorBucket(forColorIndex: star.colorIndex)
            let direction = equatorialVector(star.equatorialJ2000)
            let center = direction * sphereRadius
            // The brightest ~2 dozen stars get diffraction spikes + extra size
            // so they read as the recognizable bright stars of the sky.
            let bright = star.visualMagnitude < 1.5
            let half = starSize(magnitude: star.visualMagnitude) * (bright ? 2.3 : 1.4)
            if bright {
                appendQuad(center: center, radialDirection: direction, halfSize: half,
                           vertices: &spikeV[bucket], indices: &spikeI[bucket], uvs: &spikeUV[bucket])
            } else {
                appendQuad(center: center, radialDirection: direction, halfSize: half,
                           vertices: &glowV[bucket], indices: &glowI[bucket], uvs: &glowUV[bucket])
            }
        }

        func addBuckets(vertices: [[SIMD3<Float>]], indices: [[UInt32]], uvs: [[SIMD2<Float>]],
                        texture: TextureResource?, tag: String) {
            for bucket in bucketColors.indices where !vertices[bucket].isEmpty {
                guard let mesh = makeMesh(name: "\(tag)\(bucket)",
                                          vertices: vertices[bucket],
                                          indices: indices[bucket],
                                          uvs: uvs[bucket]) else { continue }
                let material: Material = texture.map { starMaterial(tint: bucketColors[bucket], texture: $0) }
                    ?? UnlitMaterial(color: bucketColors[bucket])
                root.addChild(ModelEntity(mesh: mesh, materials: [material]))
            }
        }

        addBuckets(vertices: glowV, indices: glowI, uvs: glowUV, texture: glowTexture, tag: "stars")
        addBuckets(vertices: spikeV, indices: spikeI, uvs: spikeUV, texture: spikeTexture, tag: "starsBright")
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

    /// Labels for named stars down to a magnitude cut. Returns the parent
    /// entity plus each label paired with its star magnitude, so the renderer
    /// can declutter by revealing fainter labels only as the view zooms in.
    static func buildStarLabels(stars: [Star], magnitudeCut: Double = 3.5)
        -> (root: Entity, tiers: [(entity: Entity, magnitude: Double)]) {
        let root = Entity()
        root.name = "starLabels"
        var tiers: [(entity: Entity, magnitude: Double)] = []
        for star in stars where star.visualMagnitude <= magnitudeCut && star.properName != nil {
            let direction = equatorialVector(star.equatorialJ2000)
            let label = makeLabel(text: star.name,
                                  color: UIColor(white: 0.9, alpha: 1),
                                  size: 1.5)
            // Offset the label slightly below the star.
            place(label: label, at: direction * sphereRadius, verticalOffset: -1.6)
            root.addChild(label)
            tiers.append((label, star.visualMagnitude))
        }
        return (root, tiers)
    }

    // MARK: Milky Way

    /// ICRS(J2000) → Galactic rotation (Hipparcos, ESA 1997). We use its
    /// transpose to place galactic-frame points into the equatorial mesh frame.
    private static let galacticToEquatorial: simd_double3x3 = {
        let toGalactic = simd_double3x3(rows: [
            SIMD3(-0.0548755604, -0.8734370902, -0.4838350155),
            SIMD3( 0.4941094279, -0.4448296300,  0.7469822445),
            SIMD3(-0.8676661490, -0.1980763734,  0.4559837762),
        ])
        return toGalactic.transpose
    }()

    /// Equatorial-mesh unit vector for a galactic coordinate (l, b).
    private static func galacticVector(longitude l: Double, latitudeDegrees b: Double) -> SIMD3<Float> {
        let br = b * AstroMath.degToRad
        let g = SIMD3<Double>(cos(br) * cos(l), cos(br) * sin(l), sin(br))
        let e = galacticToEquatorial * g
        return SIMD3(Float(e.x), Float(e.y), Float(e.z))
    }

    /// Soft band texture: transparent at the edges, brightest at the galactic
    /// equator (mapped to the V axis), giving brightness falloff with latitude.
    private static let milkyWayTexture: TextureResource? = {
        let width = 8, height = 128
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        let image = renderer.image { context in
            let space = CGColorSpaceCreateDeviceRGB()
            let tint = UIColor(red: 0.72, green: 0.78, blue: 0.95, alpha: 1)
            guard let gradient = CGGradient(colorsSpace: space,
                                            colors: [tint.withAlphaComponent(0.0).cgColor,
                                                     tint.withAlphaComponent(0.10).cgColor,
                                                     tint.withAlphaComponent(0.28).cgColor,
                                                     tint.withAlphaComponent(0.10).cgColor,
                                                     tint.withAlphaComponent(0.0).cgColor] as CFArray,
                                            locations: [0, 0.32, 0.5, 0.68, 1]) else { return }
            context.cgContext.drawLinearGradient(gradient,
                                                 start: CGPoint(x: 0, y: 0),
                                                 end: CGPoint(x: 0, y: height),
                                                 options: [])
        }
        guard let cgImage = image.cgImage else { return nil }
        return try? TextureResource(image: cgImage, withName: "milkyWay",
                                    options: .init(semantic: .color))
    }()

    /// Translucent Milky Way ribbon along the galactic plane (±14° of galactic
    /// latitude), rendered just inside the star sphere.
    static func buildMilkyWay() -> Entity {
        let root = Entity()
        root.name = "milkyWay"
        let steps = 240
        let halfWidth = 14.0
        let radius = sphereRadius * 0.985
        var vertices: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        for i in 0...steps {
            let l = Double(i) / Double(steps) * 2 * .pi
            let u = Float(i) / Float(steps)
            vertices.append(galacticVector(longitude: l, latitudeDegrees: halfWidth) * radius)
            uvs.append(SIMD2(u, 0))
            vertices.append(galacticVector(longitude: l, latitudeDegrees: -halfWidth) * radius)
            uvs.append(SIMD2(u, 1))
        }
        for i in 0..<steps {
            let a = UInt32(i * 2), b = a + 1, c = a + 2, d = a + 3
            // Both windings so the band shows regardless of view side.
            indices.append(contentsOf: [a, b, c, b, d, c, a, c, b, b, c, d])
        }

        if let mesh = makeMesh(name: "milkyWayBand", vertices: vertices, indices: indices, uvs: uvs) {
            let material: Material = milkyWayTexture.map {
                var m = UnlitMaterial(color: .white)
                m.color = .init(tint: .white, texture: .init($0))
                m.blending = .transparent(opacity: .init(floatLiteral: 1.0))
                return m
            } ?? {
                var m = UnlitMaterial(color: UIColor(red: 0.72, green: 0.78, blue: 0.95, alpha: 1))
                m.blending = .transparent(opacity: .init(floatLiteral: 0.2))
                return m
            }()
            root.addChild(ModelEntity(mesh: mesh, materials: [material]))
        }
        return root
    }

    // MARK: Reference lines (equator, ecliptic, RA/Dec grid)

    /// J2000 Julian Date, used to define the equator/ecliptic in the mesh frame.
    private static let j2000: Double = 2_451_545.0

    /// Sample a closed great/small circle as scene-space points.
    private static func circlePoints(steps: Int = 180,
                                     _ coordinate: (Double) -> EquatorialCoordinates) -> [SIMD3<Float>] {
        (0..<steps).map { i in
            equatorialVector(coordinate(Double(i) / Double(steps) * 2 * .pi))
        }
    }

    /// Append line segments joining consecutive points (closed if `closed`).
    private static func appendPolyline(_ points: [SIMD3<Float>], width: Float, closed: Bool,
                                       vertices: inout [SIMD3<Float>], indices: inout [UInt32]) {
        guard points.count > 1 else { return }
        let last = closed ? points.count : points.count - 1
        for i in 0..<last {
            appendSegment(from: points[i] * sphereRadius,
                          to: points[(i + 1) % points.count] * sphereRadius,
                          width: width, vertices: &vertices, indices: &indices)
        }
    }

    /// Celestial equator (declination 0) with an "Equator" label.
    static func buildCelestialEquator() -> Entity {
        let root = Entity()
        root.name = "celestialEquator"
        let color = UIColor(red: 0.45, green: 0.85, blue: 0.95, alpha: 1)
        var vertices: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        let points = circlePoints { ra in EquatorialCoordinates(rightAscension: ra, declination: 0) }
        appendPolyline(points, width: 0.11, closed: true, vertices: &vertices, indices: &indices)
        if let mesh = makeMesh(name: "equator", vertices: vertices, indices: indices) {
            var material = UnlitMaterial(color: color)
            material.blending = .transparent(opacity: .init(floatLiteral: 0.55))
            root.addChild(ModelEntity(mesh: mesh, materials: [material]))
        }
        let label = makeLabel(text: "EQUATOR", color: color.withAlphaComponent(0.9), size: 1.6)
        place(label: label, at: equatorialVector(EquatorialCoordinates(raHours: 3, decDegrees: 0)) * sphereRadius,
              verticalOffset: 1.4)
        root.addChild(label)
        return root
    }

    /// Ecliptic (the Sun's apparent path), tilted by the J2000 obliquity, with
    /// an "Ecliptic" label.
    static func buildEcliptic() -> Entity {
        let root = Entity()
        root.name = "ecliptic"
        let color = UIColor(red: 1.0, green: 0.82, blue: 0.38, alpha: 1)
        var vertices: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        let points = circlePoints { lambda in
            CoordinateTransforms.eclipticToEquatorial(
                EclipticCoordinates(longitude: lambda, latitude: 0), julianDate: j2000)
        }
        appendPolyline(points, width: 0.13, closed: true, vertices: &vertices, indices: &indices)
        if let mesh = makeMesh(name: "ecliptic", vertices: vertices, indices: indices) {
            var material = UnlitMaterial(color: color)
            material.blending = .transparent(opacity: .init(floatLiteral: 0.6))
            root.addChild(ModelEntity(mesh: mesh, materials: [material]))
        }
        let labelEquatorial = CoordinateTransforms.eclipticToEquatorial(
            EclipticCoordinates(longitude: 90 * AstroMath.degToRad, latitude: 0), julianDate: j2000)
        let label = makeLabel(text: "ECLIPTIC", color: color.withAlphaComponent(0.9), size: 1.6)
        place(label: label, at: equatorialVector(labelEquatorial) * sphereRadius, verticalOffset: 1.4)
        root.addChild(label)
        return root
    }

    /// RA/Dec grid: meridians every 2h and parallels every 15°, thin lines.
    static func buildCoordinateGrid() -> Entity {
        let root = Entity()
        root.name = "coordinateGrid"
        let color = UIColor(white: 0.7, alpha: 1)
        var vertices: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        // Meridians: RA = 0h, 2h, … 22h, from −80° to +80° declination.
        for hour in stride(from: 0.0, to: 24.0, by: 2.0) {
            let points: [SIMD3<Float>] = stride(from: -80.0, through: 80.0, by: 5.0).map { dec in
                equatorialVector(EquatorialCoordinates(raHours: hour, decDegrees: dec))
            }
            appendPolyline(points, width: 0.055, closed: false, vertices: &vertices, indices: &indices)
        }
        // Parallels: Dec = ±15°, ±30°, … ±75° (equator handled separately).
        for dec in stride(from: -75.0, through: 75.0, by: 15.0) where dec != 0 {
            let points = circlePoints(steps: 120) { ra in
                EquatorialCoordinates(rightAscension: ra, declination: dec * AstroMath.degToRad)
            }
            appendPolyline(points, width: 0.055, closed: true, vertices: &vertices, indices: &indices)
        }

        if let mesh = makeMesh(name: "radecGrid", vertices: vertices, indices: indices) {
            var material = UnlitMaterial(color: color)
            material.blending = .transparent(opacity: .init(floatLiteral: 0.28))
            root.addChild(ModelEntity(mesh: mesh, materials: [material]))
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

    /// Ring-style markers for Messier objects. Every object gets a designation
    /// label; "primary" ones (named or bright) show whenever deep-sky is on,
    /// while the rest are returned as `secondaryLabels` for the renderer to
    /// reveal only when the view is zoomed in.
    static func buildDeepSkyMarkers() -> (root: Entity, secondaryLabels: [Entity]) {
        let root = Entity()
        root.name = "deepSky"
        var secondaryLabels: [Entity] = []
        for object in SkyCatalog.allDeepSky where object.visualMagnitude <= deepSkyMagnitudeCut {
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

            let label = makeLabel(text: object.designation, color: color.withAlphaComponent(0.9), size: 1.2)
            place(label: label, at: direction * sphereRadius, verticalOffset: -1.8)
            let isPrimary = object.commonName != nil || object.visualMagnitude <= 6.5
            if !isPrimary {
                label.isEnabled = false
                secondaryLabels.append(label)
            }
            root.addChild(label)
        }
        return (root, secondaryLabels)
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

    /// Bundled 2K texture file key for each planet's Sky-view marker.
    static func planetTextureKey(_ planet: Planet) -> String {
        switch planet {
        case .mercury: "2k_mercury"
        case .venus: "2k_venus_atmosphere"
        case .earth: "2k_earth_daymap"
        case .mars: "2k_mars"
        case .jupiter: "2k_jupiter"
        case .saturn: "2k_saturn"
        case .uranus: "2k_uranus"
        case .neptune: "2k_neptune"
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

        func addMarker(id: String, labelText: String, color: UIColor, radius: Float, textureKey: String? = nil) {
            let holder = Entity()
            holder.name = id
            let material: Material
            if let textureKey, let texture = ScaleModelTexture.texture(key: textureKey) {
                var textured = UnlitMaterial(color: .white)
                textured.color = .init(tint: .white, texture: .init(texture))
                material = textured
            } else {
                material = UnlitMaterial(color: color)
            }
            let sphere = ModelEntity(mesh: .generateSphere(radius: radius), materials: [material])
            // Show the map the right way up and turned toward the viewer.
            sphere.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0))
            holder.addChild(sphere)
            let label = makeLabel(text: labelText, color: color, size: 1.7)
            label.position = SIMD3(0, -radius - 1.7, 0)
            holder.addChild(label)
            markers[id] = holder
            root.addChild(holder)
        }

        addMarker(id: "sun", labelText: "Sun",
                  color: UIColor(red: 1.0, green: 0.93, blue: 0.55, alpha: 1), radius: 2.6, textureKey: "2k_sun")
        addMarker(id: "moon", labelText: "Moon",
                  color: UIColor(white: 0.92, alpha: 1), radius: 2.4, textureKey: "2k_moon")
        for planet in Planet.visible {
            // Oversized so planets are easy to find in the sky.
            addMarker(id: "planet.\(planet.rawValue)", labelText: planet.name,
                      color: planetColor(planet), radius: planetMarkerRadius(planet) * 2.4,
                      textureKey: planetTextureKey(planet))
        }
        for body in MinorBodyEphemeris.bodies {
            addMarker(id: "minor.\(body.key)", labelText: body.name,
                      color: UIColor(white: 0.78, alpha: 1), radius: 0.9)
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

    // MARK: Horizon light-pollution glow

    /// Warm vertical gradient: opaque near the horizon, transparent higher up.
    private static let horizonGlowTexture: TextureResource? = {
        let width = 8, height = 128
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        let image = renderer.image { context in
            let space = CGColorSpaceCreateDeviceRGB()
            let tint = UIColor(red: 0.55, green: 0.45, blue: 0.34, alpha: 1)   // sodium-glow warm
            guard let gradient = CGGradient(colorsSpace: space,
                                            colors: [tint.withAlphaComponent(0.0).cgColor,
                                                     tint.withAlphaComponent(0.12).cgColor,
                                                     tint.withAlphaComponent(0.6).cgColor] as CFArray,
                                            locations: [0, 0.55, 1]) else { return }
            // v=0 (top, faint) → v=1 (bottom, near horizon, strong).
            context.cgContext.drawLinearGradient(gradient,
                                                 start: CGPoint(x: 0, y: 0),
                                                 end: CGPoint(x: 0, y: height),
                                                 options: [])
        }
        guard let cgImage = image.cgImage else { return nil }
        return try? TextureResource(image: cgImage, withName: "horizonGlow",
                                    options: .init(semantic: .color))
    }()

    /// Skirt of geometry hugging the horizon (world frame, just inside the star
    /// sphere so it washes over low stars). Opacity is driven by the renderer
    /// from the Bortle class to simulate light-pollution glow and extinction.
    static func buildHorizonGlow() -> Entity {
        let root = Entity()
        root.name = "horizonGlow"
        let radius = sphereRadius * 0.93
        let steps = 96
        let topAltitude = 32.0 * AstroMath.degToRad
        let bottomAltitude = -3.0 * AstroMath.degToRad
        var vertices: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        for i in 0...steps {
            let azimuth = Double(i) / Double(steps) * 2 * .pi
            let u = Float(i) / Float(steps)
            vertices.append(sceneDirection(horizontal:
                HorizontalCoordinates(altitude: topAltitude, azimuth: azimuth)) * radius)
            uvs.append(SIMD2(u, 0))
            vertices.append(sceneDirection(horizontal:
                HorizontalCoordinates(altitude: bottomAltitude, azimuth: azimuth)) * radius)
            uvs.append(SIMD2(u, 1))
        }
        for i in 0..<steps {
            let a = UInt32(i * 2), b = a + 1, c = a + 2, d = a + 3
            indices.append(contentsOf: [a, b, c, b, d, c, a, c, b, b, c, d])
        }

        if let mesh = makeMesh(name: "horizonGlow", vertices: vertices, indices: indices, uvs: uvs),
           let texture = horizonGlowTexture {
            var material = UnlitMaterial(color: .white)
            material.color = .init(tint: .white, texture: .init(texture))
            material.blending = .transparent(opacity: .init(floatLiteral: 1.0))
            root.addChild(ModelEntity(mesh: mesh, materials: [material]))
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

    // MARK: Satellite track

    /// Build the predicted sky-track polyline (world frame) from sampled
    /// scene-space points — `nil` entries are below the horizon and break the
    /// line. Adds an arrowhead at the leading (last valid) point.
    static func buildSatelliteTrack(points: [SIMD3<Float>?], color: UIColor) -> Entity {
        let root = Entity()
        root.name = "satelliteTrack"
        var vertices: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        for k in 0..<max(0, points.count - 1) {
            guard let a = points[k], let b = points[k + 1] else { continue }
            appendSegment(from: a, to: b, width: 0.45, vertices: &vertices, indices: &indices)
        }

        // Arrowhead: a small chevron at the leading end, opening backward along
        // the direction of motion.
        let valid = points.compactMap { $0 }
        if valid.count >= 2 {
            let tip = valid[valid.count - 1]
            let prev = valid[valid.count - 2]
            let motion = simd_normalize(tip - prev)
            let radial = simd_normalize(tip)
            let side = simd_normalize(simd_cross(radial, motion))
            let back = tip - motion * 2.4
            appendSegment(from: tip, to: back + side * 1.4, width: 0.5, vertices: &vertices, indices: &indices)
            appendSegment(from: tip, to: back - side * 1.4, width: 0.5, vertices: &vertices, indices: &indices)
        }

        if let mesh = makeMesh(name: "satTrack", vertices: vertices, indices: indices) {
            var material = UnlitMaterial(color: color)
            material.blending = .transparent(opacity: .init(floatLiteral: 0.85))
            root.addChild(ModelEntity(mesh: mesh, materials: [material]))
        }
        return root
    }

    // MARK: Meteor-shower radiants

    /// Labeled radiant markers (equatorial mesh frame) for active showers.
    static func buildMeteorRadiants(_ showers: [MeteorShower]) -> Entity {
        let root = Entity()
        root.name = "meteorRadiants"
        let color = UIColor(red: 1.0, green: 0.85, blue: 0.5, alpha: 1)
        for shower in showers {
            let direction = equatorialVector(shower.radiant)
            let holder = Entity()
            let burst = ModelEntity(mesh: .generateSphere(radius: 0.8),
                                    materials: [UnlitMaterial(color: color)])
            holder.addChild(burst)
            let label = makeLabel(text: "\(shower.name) radiant", color: color, size: 1.4)
            label.position = SIMD3(0, -1.8, 0)
            holder.addChild(label)
            holder.position = direction * (sphereRadius * 0.92)
            orientTowardCenter(holder, at: holder.position)
            root.addChild(holder)
        }
        return root
    }

    // MARK: - Mesh primitives

    static func makeMesh(name: String, vertices: [SIMD3<Float>], indices: [UInt32],
                         uvs: [SIMD2<Float>]? = nil) -> MeshResource? {
        guard !vertices.isEmpty else { return nil }
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(vertices)
        if let uvs, uvs.count == vertices.count {
            descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        }
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }

    /// Quad tangent to the sphere, facing the origin. When a `uvs` buffer is
    /// supplied, the four corners receive [0,1]² texture coordinates so the
    /// quad can carry a sprite (e.g. the round star glow).
    static func appendQuad(center: SIMD3<Float>, radialDirection: SIMD3<Float>, halfSize: Float,
                           vertices: inout [SIMD3<Float>], indices: inout [UInt32],
                           uvs: inout [SIMD2<Float>]) {
        let reference: SIMD3<Float> = abs(radialDirection.z) > 0.98 ? SIMD3(1, 0, 0) : SIMD3(0, 0, 1)
        let t1 = simd_normalize(simd_cross(radialDirection, reference))
        let t2 = simd_normalize(simd_cross(radialDirection, t1))
        let base = UInt32(vertices.count)
        vertices.append(center - t1 * halfSize - t2 * halfSize)
        vertices.append(center + t1 * halfSize - t2 * halfSize)
        vertices.append(center + t1 * halfSize + t2 * halfSize)
        vertices.append(center - t1 * halfSize + t2 * halfSize)
        uvs.append(contentsOf: [SIMD2(0, 1), SIMD2(1, 1), SIMD2(1, 0), SIMD2(0, 0)])
        // Both windings so the quad is visible regardless of face culling.
        indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3,
                                    base, base + 2, base + 1, base, base + 3, base + 2])
    }

    /// Overload without texture coordinates (used by non-sprite callers).
    static func appendQuad(center: SIMD3<Float>, radialDirection: SIMD3<Float>, halfSize: Float,
                           vertices: inout [SIMD3<Float>], indices: inout [UInt32]) {
        var discard: [SIMD2<Float>] = []
        appendQuad(center: center, radialDirection: radialDirection, halfSize: halfSize,
                   vertices: &vertices, indices: &indices, uvs: &discard)
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
