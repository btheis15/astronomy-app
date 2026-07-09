//
//  AstroGlyphs.swift
//  AstroSky
//
//  A custom, vector-drawn icon system so every object reads at a glance and the
//  app looks purpose-built rather than a wall of identical SF Symbols. Planets
//  are shaded spheres (Saturn with rings), deep-sky objects get a glyph per
//  morphological type, and constellations render their actual stick figure.
//
//  All glyphs are cheap, resolution-independent SwiftUI drawings sized to a
//  square `size`, suitable for list rows, detail headers and chips.
//

import SwiftUI
import simd

// MARK: - Palette

/// SwiftUI colors for object families, mirroring the AR scene's palette so the
/// 2D UI and the 3D sky agree.
enum AstroPalette {
    static func planet(_ planet: Planet) -> Color {
        switch planet {
        case .mercury: Color(red: 0.75, green: 0.72, blue: 0.68)
        case .venus:   Color(red: 0.98, green: 0.90, blue: 0.68)
        case .earth:   Color(red: 0.36, green: 0.60, blue: 0.92)
        case .mars:    Color(red: 0.90, green: 0.45, blue: 0.28)
        case .jupiter: Color(red: 0.85, green: 0.72, blue: 0.55)
        case .saturn:  Color(red: 0.90, green: 0.80, blue: 0.55)
        case .uranus:  Color(red: 0.62, green: 0.88, blue: 0.92)
        case .neptune: Color(red: 0.32, green: 0.50, blue: 0.95)
        }
    }

    static func deepSky(_ type: DeepSkyType) -> Color {
        switch type {
        case .galaxy:            Color(red: 0.98, green: 0.72, blue: 0.86)
        case .globularCluster:   Color(red: 0.98, green: 0.86, blue: 0.55)
        case .openCluster:       Color(red: 0.72, green: 0.90, blue: 0.55)
        case .nebula:            Color(red: 0.45, green: 0.86, blue: 0.90)
        case .planetaryNebula:   Color(red: 0.55, green: 0.80, blue: 0.98)
        case .supernovaRemnant:  Color(red: 0.98, green: 0.60, blue: 0.55)
        case .starCloud:         Color(red: 0.86, green: 0.86, blue: 0.98)
        case .asterism:          Color(red: 0.95, green: 0.92, blue: 0.70)
        }
    }

    /// Approximate blackbody-ish color for a star's B−V color index.
    static func star(colorIndexBV bv: Double) -> Color {
        switch bv {
        case ..<(-0.02): Color(red: 0.70, green: 0.80, blue: 1.00)   // O/B blue
        case ..<0.30:    Color(red: 0.86, green: 0.90, blue: 1.00)   // A white-blue
        case ..<0.58:    Color(red: 0.98, green: 0.98, blue: 0.94)   // F white
        case ..<0.81:    Color(red: 1.00, green: 0.96, blue: 0.80)   // G yellow
        case ..<1.40:    Color(red: 1.00, green: 0.82, blue: 0.58)   // K orange
        default:         Color(red: 1.00, green: 0.66, blue: 0.48)   // M red-orange
        }
    }

    static let satellite = Color(red: 0.55, green: 0.95, blue: 0.70)
    static let minorBody  = Color(red: 0.80, green: 0.76, blue: 0.66)
    static let sun        = Color(red: 1.00, green: 0.80, blue: 0.30)
    static let moon       = Color(red: 0.90, green: 0.90, blue: 0.86)
}

private extension Color {
    /// Cheap lightening/darkening for sphere shading via opacity over white/black.
    func lighter(_ amount: Double) -> Color { self.mix(with: .white, by: amount) }
    func darker(_ amount: Double) -> Color { self.mix(with: .black, by: amount) }
}

// MARK: - Sphere shading

/// A shaded sphere: soft top-left specular highlight falling to a darker limb,
/// the building block for planet and moon glyphs.
private struct ShadedSphere: View {
    let base: Color
    let diameter: CGFloat
    var highlight: Double = 0.55
    var shadow: Double = 0.45

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [base.lighter(highlight), base, base.darker(shadow)],
                    center: UnitPoint(x: 0.34, y: 0.30),
                    startRadius: 0,
                    endRadius: diameter * 0.62
                )
            )
            .overlay(
                Circle().strokeBorder(base.darker(0.35).opacity(0.6), lineWidth: max(0.5, diameter * 0.02))
            )
            .frame(width: diameter, height: diameter)
    }
}

// MARK: - Planet

struct PlanetGlyph: View {
    let planet: Planet
    var size: CGFloat = 28

    var body: some View {
        let base = AstroPalette.planet(planet)
        ZStack {
            if planet == .saturn { SaturnRings(color: base, size: size) }

            ShadedSphere(base: base, diameter: bodySize)
                .overlay { bands(base: base).clipShape(Circle()) }

            if planet == .saturn {
                // Front half of the ring, drawn over the disk.
                SaturnRings(color: base, size: size, frontHalfOnly: true)
            }
        }
        .frame(width: size, height: size)
    }

    /// Saturn's disk is inset to leave room for its rings.
    private var bodySize: CGFloat { planet == .saturn ? size * 0.62 : size * 0.86 }

    @ViewBuilder
    private func bands(base: Color) -> some View {
        switch planet {
        case .jupiter:
            VStack(spacing: bodySize * 0.06) {
                band(base.darker(0.18), h: bodySize * 0.10)
                band(base.lighter(0.16), h: bodySize * 0.08)
                band(base.darker(0.24), h: bodySize * 0.12)
                band(base.lighter(0.10), h: bodySize * 0.07)
            }
            .opacity(0.9)
        case .saturn:
            VStack(spacing: bodySize * 0.10) {
                band(base.darker(0.14), h: bodySize * 0.10)
                band(base.lighter(0.12), h: bodySize * 0.09)
            }
            .opacity(0.8)
        case .neptune, .uranus:
            band(base.lighter(0.18), h: bodySize * 0.10).opacity(0.7)
        default:
            EmptyView()
        }
    }

    private func band(_ color: Color, h: CGFloat) -> some View {
        Capsule().fill(color).frame(height: h)
    }
}

/// A tilted ring system for Saturn. Draws the back half by default; pass
/// `frontHalfOnly` to overlay the near arc on top of the disk.
private struct SaturnRings: View {
    let color: Color
    let size: CGFloat
    var frontHalfOnly = false

    var body: some View {
        Ellipse()
            .strokeBorder(
                LinearGradient(colors: [color.opacity(0.0),
                                        color.lighter(0.25).opacity(0.95),
                                        color.opacity(0.0)],
                               startPoint: .leading, endPoint: .trailing),
                lineWidth: size * 0.07
            )
            .frame(width: size * 0.98, height: size * 0.40)
            .rotationEffect(.degrees(-20))
            .mask(alignment: frontHalfOnly ? .bottom : .top) {
                Rectangle().frame(height: size / 2)
            }
    }
}

// MARK: - Sun & Moon

struct SunGlyph: View {
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [AstroPalette.sun.opacity(0.55), .clear],
                                     center: .center, startRadius: size * 0.18, endRadius: size * 0.55))
            Circle()
                .fill(RadialGradient(colors: [.white, AstroPalette.sun, Color(red: 1, green: 0.55, blue: 0.15)],
                                     center: UnitPoint(x: 0.4, y: 0.38),
                                     startRadius: 0, endRadius: size * 0.42))
                .frame(width: size * 0.68, height: size * 0.68)
        }
        .frame(width: size, height: size)
    }
}

struct MoonGlyph: View {
    var size: CGFloat = 28

    var body: some View {
        ShadedSphere(base: AstroPalette.moon, diameter: size * 0.84, highlight: 0.35, shadow: 0.4)
            .overlay {
                // A couple of soft maria for texture.
                Circle().fill(Color.black.opacity(0.08))
                    .frame(width: size * 0.22, height: size * 0.22)
                    .offset(x: -size * 0.10, y: -size * 0.06)
                Circle().fill(Color.black.opacity(0.06))
                    .frame(width: size * 0.14, height: size * 0.14)
                    .offset(x: size * 0.12, y: size * 0.12)
            }
            .clipShape(Circle())
            .frame(width: size, height: size)
    }
}

// MARK: - Star / satellite / minor body

struct StarGlyph: View {
    var magnitude: Double = 1.5
    var colorIndexBV: Double = 0.5
    var size: CGFloat = 28

    var body: some View {
        let tint = AstroPalette.star(colorIndexBV: colorIndexBV)
        // Brighter stars draw a touch larger.
        let scale = max(0.55, min(1.0, 1.0 - (magnitude - 0.5) * 0.11))
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [tint.opacity(0.5), .clear],
                                     center: .center, startRadius: 0, endRadius: size * 0.5))
            Image(systemName: "sparkle")
                .font(.system(size: size * 0.62 * scale))
                .foregroundStyle(tint)
                .shadow(color: tint.opacity(0.8), radius: size * 0.06)
        }
        .frame(width: size, height: size)
    }
}

struct SatelliteGlyph: View {
    var size: CGFloat = 28

    var body: some View {
        let tint = AstroPalette.satellite
        HStack(spacing: size * 0.05) {
            solarPanel(tint: tint)
            RoundedRectangle(cornerRadius: size * 0.04)
                .fill(LinearGradient(colors: [Color(white: 0.92), Color(white: 0.6)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.20, height: size * 0.30)
                .overlay(RoundedRectangle(cornerRadius: size * 0.04)
                    .strokeBorder(Color.black.opacity(0.25), lineWidth: 0.5))
            solarPanel(tint: tint)
        }
        .rotationEffect(.degrees(-18))
        .frame(width: size, height: size)
    }

    private func solarPanel(tint: Color) -> some View {
        RoundedRectangle(cornerRadius: size * 0.02)
            .fill(tint.opacity(0.9))
            .overlay {
                GeometryReader { geo in
                    Path { p in
                        let x = geo.size.width / 2
                        p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: geo.size.height))
                        for j in 1..<3 {
                            let y = geo.size.height * CGFloat(j) / 3
                            p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: geo.size.width, y: y))
                        }
                    }
                    .stroke(Color.black.opacity(0.3), lineWidth: 0.5)
                }
            }
            .frame(width: size * 0.22, height: size * 0.44)
    }
}

struct MinorBodyGlyph: View {
    var size: CGFloat = 28

    var body: some View {
        // A lumpy asteroid: a slightly squashed shaded blob with a crater.
        ShadedSphere(base: AstroPalette.minorBody, diameter: size * 0.64, highlight: 0.3, shadow: 0.5)
            .scaleEffect(x: 1.12, y: 0.88)
            .overlay {
                Circle().fill(Color.black.opacity(0.12))
                    .frame(width: size * 0.12, height: size * 0.12)
                    .offset(x: size * 0.06, y: -size * 0.02)
            }
            .rotationEffect(.degrees(-18))
            .frame(width: size, height: size)
    }
}

// MARK: - Deep sky

struct DeepSkyGlyph: View {
    let type: DeepSkyType
    var size: CGFloat = 28

    var body: some View {
        let tint = AstroPalette.deepSky(type)
        Canvas { context, canvasSize in
            let rect = CGRect(origin: .zero, size: canvasSize)
            let c = CGPoint(x: rect.midX, y: rect.midY)
            let r = min(rect.width, rect.height) / 2
            switch type {
            case .galaxy:           drawGalaxy(context, center: c, radius: r, tint: tint)
            case .globularCluster:  drawCluster(context, center: c, radius: r, tint: tint, points: DeepSkyGlyph.globularPoints, dense: true)
            case .openCluster:      drawCluster(context, center: c, radius: r, tint: tint, points: DeepSkyGlyph.openPoints, dense: false)
            case .nebula:           drawNebula(context, center: c, radius: r, tint: tint)
            case .planetaryNebula:  drawPlanetaryNebula(context, center: c, radius: r, tint: tint)
            case .supernovaRemnant: drawSupernova(context, center: c, radius: r, tint: tint)
            case .starCloud:        drawCluster(context, center: c, radius: r, tint: tint, points: DeepSkyGlyph.cloudPoints, dense: true)
            case .asterism:         drawAsterism(context, center: c, radius: r, tint: tint)
            }
        }
        .frame(width: size, height: size)
    }

    // MARK: Drawing

    private func drawGalaxy(_ ctx: GraphicsContext, center c: CGPoint, radius r: CGFloat, tint: Color) {
        // Two logarithmic spiral arms + a bright core.
        for arm in 0..<2 {
            var path = Path()
            let phase = Double(arm) * .pi
            for i in 0...40 {
                let t = Double(i) / 40.0
                let angle = t * 3.0 * .pi + phase
                let radius = r * 0.9 * CGFloat(t)
                let p = CGPoint(x: c.x + radius * CGFloat(cos(angle)),
                                y: c.y + radius * CGFloat(sin(angle)) * 0.72)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            ctx.stroke(path, with: .color(tint.opacity(0.85)), style: StrokeStyle(lineWidth: r * 0.16, lineCap: .round))
        }
        var core = ctx
        core.addFilter(.blur(radius: r * 0.12))
        core.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.28, y: c.y - r * 0.20,
                                         width: r * 0.56, height: r * 0.40)),
                  with: .color(.white.opacity(0.95)))
    }

    private func drawCluster(_ ctx: GraphicsContext, center c: CGPoint, radius r: CGFloat,
                             tint: Color, points: [CGPoint], dense: Bool) {
        if dense {
            var glow = ctx
            glow.addFilter(.blur(radius: r * 0.25))
            glow.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.7, y: c.y - r * 0.7, width: r * 1.4, height: r * 1.4)),
                      with: .color(tint.opacity(0.28)))
        }
        for p in points {
            let dot = CGPoint(x: c.x + p.x * r, y: c.y + p.y * r)
            let d = r * (dense ? 0.13 : 0.17)
            ctx.fill(Path(ellipseIn: CGRect(x: dot.x - d / 2, y: dot.y - d / 2, width: d, height: d)),
                     with: .color(dense ? tint.opacity(0.95) : tint))
        }
    }

    private func drawNebula(_ ctx: GraphicsContext, center c: CGPoint, radius r: CGFloat, tint: Color) {
        var soft = ctx
        soft.addFilter(.blur(radius: r * 0.22))
        for (dx, dy, s) in [(-0.2, -0.1, 0.9), (0.22, 0.05, 0.8), (0.0, 0.2, 0.7)] {
            let rect = CGRect(x: c.x + CGFloat(dx) * r - r * CGFloat(s) / 2,
                              y: c.y + CGFloat(dy) * r - r * CGFloat(s) / 2,
                              width: r * CGFloat(s), height: r * CGFloat(s))
            soft.fill(Path(ellipseIn: rect), with: .color(tint.opacity(0.55)))
        }
        // A few embedded stars.
        for p in [CGPoint(x: -0.1, y: -0.05), CGPoint(x: 0.18, y: 0.12)] {
            let dot = CGPoint(x: c.x + p.x * r, y: c.y + p.y * r)
            ctx.fill(Path(ellipseIn: CGRect(x: dot.x - 1, y: dot.y - 1, width: 2, height: 2)),
                     with: .color(.white))
        }
    }

    private func drawPlanetaryNebula(_ ctx: GraphicsContext, center c: CGPoint, radius r: CGFloat, tint: Color) {
        let ringRect = CGRect(x: c.x - r * 0.6, y: c.y - r * 0.6, width: r * 1.2, height: r * 1.2)
        var glow = ctx
        glow.addFilter(.blur(radius: r * 0.12))
        glow.stroke(Path(ellipseIn: ringRect), with: .color(tint.opacity(0.9)), lineWidth: r * 0.22)
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.09, y: c.y - r * 0.09, width: r * 0.18, height: r * 0.18)),
                 with: .color(.white))
    }

    private func drawSupernova(_ ctx: GraphicsContext, center c: CGPoint, radius r: CGFloat, tint: Color) {
        // Irregular expanding filaments.
        for i in 0..<9 {
            let angle = Double(i) / 9.0 * 2 * .pi
            let len = r * (i % 2 == 0 ? 0.9 : 0.6)
            var path = Path()
            path.move(to: c)
            path.addLine(to: CGPoint(x: c.x + len * CGFloat(cos(angle)),
                                     y: c.y + len * CGFloat(sin(angle))))
            ctx.stroke(path, with: .color(tint.opacity(0.85)), style: StrokeStyle(lineWidth: r * 0.09, lineCap: .round))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.12, y: c.y - r * 0.12, width: r * 0.24, height: r * 0.24)),
                 with: .color(.white.opacity(0.9)))
    }

    private func drawAsterism(_ ctx: GraphicsContext, center c: CGPoint, radius r: CGFloat, tint: Color) {
        let pts = [CGPoint(x: -0.5, y: -0.3), CGPoint(x: 0.0, y: -0.5),
                   CGPoint(x: 0.45, y: -0.1), CGPoint(x: 0.15, y: 0.45), CGPoint(x: -0.4, y: 0.3)]
            .map { CGPoint(x: c.x + $0.x * r, y: c.y + $0.y * r) }
        var path = Path()
        path.addLines(pts)
        ctx.stroke(path, with: .color(tint.opacity(0.5)), lineWidth: r * 0.05)
        for p in pts {
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 0.09, y: p.y - r * 0.09, width: r * 0.18, height: r * 0.18)),
                     with: .color(tint))
        }
    }

    // Stable, hand-placed point sets (no runtime randomness).
    private static let globularPoints: [CGPoint] = [
        .init(x: 0, y: 0), .init(x: -0.28, y: -0.12), .init(x: 0.26, y: -0.2), .init(x: 0.1, y: 0.28),
        .init(x: -0.2, y: 0.24), .init(x: 0.34, y: 0.1), .init(x: -0.36, y: 0.06), .init(x: 0.04, y: -0.34),
        .init(x: 0.18, y: 0.06), .init(x: -0.12, y: -0.24), .init(x: -0.06, y: 0.12), .init(x: 0.22, y: -0.06),
    ]
    private static let openPoints: [CGPoint] = [
        .init(x: -0.35, y: -0.28), .init(x: 0.2, y: -0.34), .init(x: 0.38, y: 0.1),
        .init(x: -0.1, y: 0.1), .init(x: 0.06, y: 0.4), .init(x: -0.42, y: 0.22),
    ]
    private static let cloudPoints: [CGPoint] = [
        .init(x: -0.42, y: -0.1), .init(x: -0.24, y: -0.28), .init(x: -0.1, y: 0.06), .init(x: 0.02, y: -0.16),
        .init(x: 0.16, y: 0.2), .init(x: 0.3, y: -0.06), .init(x: 0.42, y: 0.14), .init(x: -0.16, y: 0.3),
        .init(x: 0.24, y: 0.36), .init(x: -0.34, y: 0.2), .init(x: 0.1, y: -0.36), .init(x: -0.02, y: 0.4),
    ]
}

// MARK: - Constellation stick figure

/// Renders a constellation's actual stick figure, projected from its member
/// stars onto the tangent plane at the figure's centroid and scaled to fit.
struct ConstellationGlyph: View {
    let constellation: Constellation
    var size: CGFloat = 28
    var tint: Color = Color(red: 0.62, green: 0.70, blue: 1.0)

    var body: some View {
        Canvas { context, canvasSize in
            let segments = ConstellationGlyph.projected(constellation)
            guard !segments.points.isEmpty else { return }
            let inset: CGFloat = size * 0.14
            let box = CGRect(origin: .zero, size: canvasSize).insetBy(dx: inset, dy: inset)

            func place(_ p: CGPoint) -> CGPoint {
                CGPoint(x: box.minX + p.x * box.width, y: box.minY + p.y * box.height)
            }

            for line in segments.lines {
                var path = Path()
                path.move(to: place(line.0))
                path.addLine(to: place(line.1))
                context.stroke(path, with: .color(tint.opacity(0.55)),
                               style: StrokeStyle(lineWidth: 1, lineCap: .round))
            }
            for star in segments.points {
                let p = place(star.point)
                let d = star.bright ? size * 0.11 : size * 0.07
                context.fill(Path(ellipseIn: CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d)),
                             with: .color(.white))
            }
        }
        .frame(width: size, height: size)
    }

    struct Projected {
        var points: [(point: CGPoint, bright: Bool)]
        var lines: [(CGPoint, CGPoint)]
    }

    /// Project the figure's stars to normalized [0,1] coordinates (y down).
    static func projected(_ constellation: Constellation) -> Projected {
        let pairs = constellation.starPairs
        guard !pairs.isEmpty else { return Projected(points: [], lines: []) }

        // Unique stars and centroid direction.
        var seen = Set<String>()
        let stars = pairs.flatMap { [$0.0, $0.1] }.filter { seen.insert($0.id).inserted }
        var centroid = SIMD3<Double>.zero
        for s in stars { centroid += s.equatorialJ2000.unitVector }
        let cl = simd_length(centroid)
        guard cl > 0 else { return Projected(points: [], lines: []) }
        let normal = centroid / cl

        // Tangent basis at the centroid (east, north).
        let up = SIMD3<Double>(0, 0, 1)
        var east = simd_cross(up, normal)
        if simd_length(east) < 1e-6 { east = SIMD3<Double>(1, 0, 0) }
        east = simd_normalize(east)
        let north = simd_normalize(simd_cross(normal, east))

        func project(_ eq: EquatorialCoordinates) -> CGPoint {
            let v = eq.unitVector
            return CGPoint(x: simd_dot(v, east), y: simd_dot(v, north))
        }

        let brightThreshold = (stars.map(\.visualMagnitude).min() ?? 0) + 1.5
        let projectedStars = stars.map {
            (id: $0.id, raw: project($0.equatorialJ2000), bright: $0.visualMagnitude <= brightThreshold)
        }

        // Normalize to [0,1] preserving aspect ratio (centered).
        let xs = projectedStars.map(\.raw.x), ys = projectedStars.map(\.raw.y)
        let minX = xs.min() ?? 0, maxX = xs.max() ?? 1
        let minY = ys.min() ?? 0, maxY = ys.max() ?? 1
        let span = max(maxX - minX, maxY - minY, 1e-6)
        let offX = (span - (maxX - minX)) / 2
        let offY = (span - (maxY - minY)) / 2

        func normalize(_ raw: CGPoint) -> CGPoint {
            // Flip x so east points right→left matches the sky mirror, y down.
            let nx = (Double(raw.x) - minX + offX) / span
            let ny = (Double(raw.y) - minY + offY) / span
            return CGPoint(x: 1 - nx, y: 1 - ny)
        }

        var byID: [String: CGPoint] = [:]
        var points: [(point: CGPoint, bright: Bool)] = []
        for s in projectedStars {
            let p = normalize(s.raw)
            byID[s.id] = p
            points.append((p, s.bright))
        }
        let lines: [(CGPoint, CGPoint)] = pairs.compactMap { pair in
            guard let a = byID[pair.0.id], let b = byID[pair.1.id] else { return nil }
            return (a, b)
        }
        return Projected(points: points, lines: lines)
    }
}

// MARK: - Unified object glyph

/// Picks the right custom glyph for any catalog object. Kept unary (single
/// root) so it stays cheap inside list rows.
struct ObjectGlyph: View {
    let object: any CelestialObject
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            switch object.kind {
            case .planet:
                if let p = object as? PlanetObject { PlanetGlyph(planet: p.planet, size: size) }
                else { PlanetGlyph(planet: .mars, size: size) }
            case .sun:
                SunGlyph(size: size)
            case .moon:
                MoonGlyph(size: size)
            case .deepSky:
                if let d = object as? DeepSkyObject { DeepSkyGlyph(type: d.type, size: size) }
                else { DeepSkyGlyph(type: .nebula, size: size) }
            case .star:
                if let s = object as? Star {
                    StarGlyph(magnitude: s.visualMagnitude, colorIndexBV: s.colorIndex, size: size)
                } else {
                    StarGlyph(size: size)
                }
            case .satellite:
                SatelliteGlyph(size: size)
            case .minorBody:
                MinorBodyGlyph(size: size)
            }
        }
        .frame(width: size, height: size)
    }
}
