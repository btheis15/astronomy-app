//
//  EyepiecePreviewView.swift
//  AstroSky
//
//  A simulated eyepiece field: the true circular field of view with the object
//  drawn to scale and rendered the way it actually appears at the eyepiece —
//  faint and low-contrast, with a scatter of field stars, and morphology that
//  matches the object's type (galaxy halo + core, resolved globular, nebular
//  cloud, ringed planet, lunar phase, and so on). This is an honest visual
//  impression, not a long-exposure photo.
//

import SwiftUI

struct EyepiecePreviewView: View {
    let object: any CelestialObject
    let optics: OpticsResult
    let angularSizeRadians: Double?
    let bortleClass: Int
    var julianDate: Double = 0

    private var fillFraction: Double {
        guard let size = angularSizeRadians else { return 0 }
        return TelescopeMath.fractionOfField(objectAngularRadians: size, trueFOVRadians: optics.trueFOVRadians)
    }

    var body: some View {
        Canvas { context, size in
            let diameter = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let fieldRect = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2,
                                   width: diameter, height: diameter)

            // Sky background: nearly black under dark skies, a faint wash under
            // light pollution.
            let glow = Double(bortleClass - 1) / 8.0
            let sky = Color(red: 0.02 + glow * 0.10, green: 0.02 + glow * 0.08, blue: 0.05 + glow * 0.11)
            context.fill(Path(ellipseIn: fieldRect), with: .color(sky))

            var inner = context
            inner.clip(to: Path(ellipseIn: fieldRect))

            // Field stars sit behind the target.
            if object.kind != .sun {
                drawFieldStars(&inner, center: center, diameter: diameter, glow: glow)
            }

            let dim = 1.0 - glow * 0.5
            drawObject(&inner, center: center, fieldDiameter: diameter, dim: dim)

            // Field stop ring.
            context.stroke(Path(ellipseIn: fieldRect), with: .color(.gray.opacity(0.55)), lineWidth: 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay(alignment: .bottom) { caption }
    }

    @ViewBuilder private var caption: some View {
        VStack(spacing: 2) {
            if fillFraction > 1 {
                Text("Extends beyond the field of view")
            } else if !AngularSizeSource.hasMeasuredSize(object) && object.kind == .deepSky {
                Text("Size estimated")
            }
            Text("\(Int(optics.magnification))× · \(optics.trueFOVDegrees, specifier: "%.2f")° field")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.bottom, 4)
    }

    // MARK: - Deterministic RNG (stable per object across launches)

    private func makeRNG(salt: String = "") -> SeededRNG {
        SeededRNG(seed: Self.fnv1a(object.id + salt))
    }

    private static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in string.utf8 { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        return hash
    }

    // MARK: - Field stars

    private func drawFieldStars(_ context: inout GraphicsContext, center: CGPoint,
                                diameter: CGFloat, glow: Double) {
        var rng = makeRNG(salt: "stars")
        let radius = diameter / 2
        // Light pollution washes out the faintest field stars.
        let count = Int(110 * (1.0 - glow * 0.55))
        for _ in 0..<count {
            // Uniform within the disk.
            let a = rng.next() * 2 * .pi
            let r = radius * CGFloat(sqrt(rng.next())) * 0.99
            let p = CGPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r)
            let bright = rng.next()
            let dotR = CGFloat(0.4 + bright * bright * 1.7)
            var tint = Color.white
            let hue = rng.next()
            if hue > 0.92 { tint = Color(red: 1.0, green: 0.8, blue: 0.6) }       // warm
            else if hue < 0.08 { tint = Color(red: 0.75, green: 0.83, blue: 1.0) } // blue
            let alpha = 0.18 + bright * 0.8
            context.fill(Path(ellipseIn: CGRect(x: p.x - dotR, y: p.y - dotR, width: dotR * 2, height: dotR * 2)),
                         with: .color(tint.opacity(alpha)))
        }
    }

    // MARK: - Object

    private func drawObject(_ context: inout GraphicsContext, center: CGPoint,
                            fieldDiameter: CGFloat, dim: Double) {
        switch object {
        case is SunObject:
            drawSun(&context, center: center, fieldDiameter: fieldDiameter)
        case is MoonObject:
            drawMoon(&context, center: center, fieldDiameter: fieldDiameter, dim: dim)
        case let planet as PlanetObject:
            drawPlanet(planet, &context, center: center, fieldDiameter: fieldDiameter, dim: dim)
        case let deepSky as DeepSkyObject:
            drawDeepSky(deepSky, &context, center: center, fieldDiameter: fieldDiameter, dim: dim)
        case let star as Star:
            drawStar(&context, center: center, colorIndex: star.colorIndex, dim: dim)
        default:
            drawStar(&context, center: center, colorIndex: 0.6, dim: dim)
        }
    }

    private var objectPixels: CGFloat { CGFloat(min(1.0, fillFraction)) }

    // MARK: Sun

    private func drawSun(_ context: inout GraphicsContext, center: CGPoint, fieldDiameter: CGFloat) {
        let r = fieldDiameter * 0.22
        context.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)),
                     with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.95, blue: 0.8),
                                                             Color(red: 1, green: 0.7, blue: 0.3)]),
                                           center: center, startRadius: 0, endRadius: r))
        // A couple of sunspots.
        var rng = makeRNG(salt: "sun")
        for _ in 0..<3 {
            let a = rng.next() * 2 * .pi
            let d = CGFloat(rng.next()) * r * 0.7
            let sp = CGPoint(x: center.x + cos(a) * d, y: center.y + sin(a) * d)
            let sr = r * CGFloat(0.05 + rng.next() * 0.05)
            context.fill(Path(ellipseIn: CGRect(x: sp.x - sr, y: sp.y - sr, width: sr * 2, height: sr * 2)),
                         with: .color(.black.opacity(0.5)))
        }
        context.draw(Text("☀︎ Use a solar filter").font(.caption.bold()).foregroundStyle(.red),
                     at: CGPoint(x: center.x, y: center.y + r + 18))
    }

    // MARK: Moon

    private func drawMoon(_ context: inout GraphicsContext, center: CGPoint, fieldDiameter: CGFloat, dim: Double) {
        let radius = max(objectPixels * fieldDiameter / 2, 40)
        let phase = MoonEphemeris.phase(julianDate: julianDate)
        let lit = Color(white: 0.86 * dim)
        let dark = Color(white: 0.12)
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)

        context.fill(Path(ellipseIn: rect), with: .color(dark))
        // Lit semicircle (right while waxing).
        var lit1 = Path()
        lit1.addArc(center: center, radius: radius, startAngle: .degrees(-90), endAngle: .degrees(90),
                    clockwise: !phase.isWaxing)
        lit1.closeSubpath()
        context.fill(lit1, with: .color(lit))
        // Terminator ellipse.
        let f = phase.illuminatedFraction
        let tw = 2 * radius * CGFloat(abs(2 * f - 1))
        let tRect = CGRect(x: center.x - tw / 2, y: center.y - radius, width: tw, height: 2 * radius)
        context.fill(Path(ellipseIn: tRect), with: .color(f > 0.5 ? lit : dark))

        // Maria + a couple of craters, only on the lit side, clipped to the disk.
        var disk = context
        disk.clip(to: Path(ellipseIn: rect))
        var rng = makeRNG(salt: "moon")
        for _ in 0..<6 {
            let a = rng.next() * 2 * .pi
            let d = CGFloat(rng.next()) * radius * 0.8
            let p = CGPoint(x: center.x + cos(a) * d, y: center.y + sin(a) * d)
            let mr = radius * CGFloat(0.08 + rng.next() * 0.16)
            disk.fill(Path(ellipseIn: CGRect(x: p.x - mr, y: p.y - mr, width: mr * 2, height: mr * 2)),
                      with: .color(.black.opacity(0.10)))
        }
    }

    // MARK: Planets

    private func drawPlanet(_ planet: PlanetObject, _ context: inout GraphicsContext, center: CGPoint,
                            fieldDiameter: CGFloat, dim: Double) {
        // True-to-scale disk, with a floor so features remain legible; boost with
        // higher magnification (the eyepiece is selectable).
        let trueR = objectPixels * fieldDiameter / 2
        let radius = max(trueR, 6)
        let base = AstroPalette.planet(planet.planet)
        let position = PlanetEphemeris.position(of: planet.planet, julianDate: julianDate)

        if planet.planet == .saturn {
            drawRing(&context, center: center, planetRadius: radius, back: true)
        }

        // Shaded disk.
        let diskRect = CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)
        context.fill(Path(ellipseIn: diskRect), with: .radialGradient(
            Gradient(colors: [mix(base, .white, 0.35), base, mix(base, .black, 0.4)]),
            center: CGPoint(x: center.x - radius * 0.3, y: center.y - radius * 0.3),
            startRadius: 0, endRadius: radius * 1.15))

        var disk = context
        disk.clip(to: Path(ellipseIn: diskRect))
        switch planet.planet {
        case .jupiter:
            for (dy, shade) in [(-0.45, -0.2), (-0.15, 0.15), (0.12, -0.28), (0.4, 0.1)] as [(Double, Double)] {
                let y = center.y + CGFloat(dy) * radius
                disk.fill(Path(CGRect(x: center.x - radius, y: y, width: 2 * radius, height: radius * 0.16)),
                          with: .color((shade < 0 ? mix(base, .black, -shade) : mix(base, .white, shade)).opacity(0.9)))
            }
        case .mars:
            // Polar cap + a dark albedo patch.
            disk.fill(Path(ellipseIn: CGRect(x: center.x - radius * 0.4, y: center.y - radius,
                                             width: radius * 0.8, height: radius * 0.5)),
                      with: .color(.white.opacity(0.85)))
            disk.fill(Path(ellipseIn: CGRect(x: center.x - radius * 0.1, y: center.y,
                                             width: radius * 0.7, height: radius * 0.5)),
                      with: .color(mix(base, .black, 0.35).opacity(0.6)))
        case .saturn:
            for dy in [-0.3, 0.05] {
                let y = center.y + CGFloat(dy) * radius
                disk.fill(Path(CGRect(x: center.x - radius, y: y, width: 2 * radius, height: radius * 0.12)),
                          with: .color(mix(base, .black, 0.15).opacity(0.7)))
            }
        default:
            break
        }

        // Phase shadow for the inner planets (Mercury/Venus, and slightly Mars).
        let illuminated = (1.0 + cos(position.phaseAngle)) / 2.0
        if illuminated < 0.97 && (planet.planet == .mercury || planet.planet == .venus || planet.planet == .mars) {
            let shadowShift = radius * CGFloat(2 * (1 - illuminated))
            disk.fill(Path(ellipseIn: CGRect(x: center.x - radius + shadowShift, y: center.y - radius,
                                             width: 2 * radius, height: 2 * radius)),
                      with: .color(.black.opacity(0.72)))
        }

        if planet.planet == .saturn {
            drawRing(&context, center: center, planetRadius: radius, back: false)
        }

        if planet.planet == .jupiter {
            drawGalileanMoons(&context, center: center, planetRadius: radius, dim: dim)
        }
        _ = dim
    }

    private func drawRing(_ context: inout GraphicsContext, center: CGPoint, planetRadius: CGFloat, back: Bool) {
        let rx = planetRadius * 2.1, ry = planetRadius * 0.7
        var ring = context
        ring.translateBy(x: center.x, y: center.y)
        ring.rotate(by: .degrees(-20))
        let halfHeight: CGFloat = 400
        ring.clip(to: Path(CGRect(x: -500, y: back ? -halfHeight : 0, width: 1000, height: halfHeight)))
        let outer = CGRect(x: -rx, y: -ry, width: 2 * rx, height: 2 * ry)
        let inner = CGRect(x: -rx * 0.62, y: -ry * 0.62, width: 2 * rx * 0.62, height: 2 * ry * 0.62)
        var path = Path()
        path.addEllipse(in: outer)
        path.addEllipse(in: inner)
        let gold = Color(red: 0.90, green: 0.82, blue: 0.60)
        ring.fill(path, with: .color(gold.opacity(0.9)), style: FillStyle(eoFill: true))
    }

    private func drawGalileanMoons(_ context: inout GraphicsContext, center: CGPoint,
                                   planetRadius: CGFloat, dim: Double) {
        var rng = makeRNG(salt: "moons")
        let offsets: [CGFloat] = [-4.5, -2.4, 2.0, 3.8]
        for off in offsets {
            let jitter = CGFloat(rng.next() - 0.5) * 0.4
            let p = CGPoint(x: center.x + (off + jitter) * planetRadius,
                            y: center.y + CGFloat(rng.next() - 0.5) * planetRadius * 0.5)
            let mr: CGFloat = 1.6
            context.fill(Path(ellipseIn: CGRect(x: p.x - mr, y: p.y - mr, width: mr * 2, height: mr * 2)),
                         with: .color(.white.opacity(0.9 * dim)))
        }
    }

    // MARK: Deep sky

    private func drawDeepSky(_ deepSky: DeepSkyObject, _ context: inout GraphicsContext, center: CGPoint,
                             fieldDiameter: CGFloat, dim: Double) {
        let radius = max(objectPixels * fieldDiameter / 2, 4)
        // Deep-sky objects look faint and near-monochrome to the eye; give only
        // a subtle tint over grayscale.
        let tint = mix(Color(uiColor: SkySceneBuilder.deepSkyColor(for: deepSky.type)), .white, 0.55).opacity(dim)

        switch deepSky.type {
        case .galaxy:
            drawGalaxy(&context, center: center, radius: radius, ratio: DeepSkySizes.axisRatio(for: deepSky), tint: tint)
        case .nebula:
            drawNebula(&context, center: center, radius: radius, tint: tint, wispy: false)
        case .supernovaRemnant:
            drawNebula(&context, center: center, radius: radius, tint: tint, wispy: true)
        case .planetaryNebula:
            drawPlanetary(&context, center: center, radius: radius, tint: tint)
        case .globularCluster:
            drawGlobular(&context, center: center, radius: radius, tint: tint)
        case .openCluster, .asterism, .starCloud:
            drawOpenCluster(&context, center: center, radius: radius,
                            count: deepSky.type == .asterism ? 14 : 40)
        }
    }

    private func drawGalaxy(_ context: inout GraphicsContext, center: CGPoint, radius: CGFloat,
                            ratio: Double, tint: Color) {
        var paRNG = makeRNG(salt: "pa")
        let angle = Angle.degrees(paRNG.next() * 180)
        var layer = context
        layer.translateBy(x: center.x, y: center.y)
        layer.rotate(by: angle)
        let r = radius, ry = radius * CGFloat(ratio)
        // Smooth halo.
        var halo = layer
        halo.addFilter(.blur(radius: r * 0.25))
        halo.fill(Path(ellipseIn: CGRect(x: -r, y: -ry, width: 2 * r, height: 2 * ry)),
                  with: .radialGradient(Gradient(colors: [tint.opacity(0.9), tint.opacity(0)]),
                                        center: .zero, startRadius: 0, endRadius: r))
        // Bright stellar core.
        let coreR = max(r * 0.18, 2)
        layer.fill(Path(ellipseIn: CGRect(x: -coreR, y: -coreR, width: 2 * coreR, height: 2 * coreR)),
                   with: .radialGradient(Gradient(colors: [.white.opacity(0.95), tint.opacity(0)]),
                                         center: .zero, startRadius: 0, endRadius: coreR * 1.6))
    }

    private func drawNebula(_ context: inout GraphicsContext, center: CGPoint, radius: CGFloat,
                            tint: Color, wispy: Bool) {
        var rng = makeRNG(salt: "neb")
        var layer = context
        layer.addFilter(.blur(radius: radius * (wispy ? 0.12 : 0.22)))
        let blobs = wispy ? 8 : 5
        for _ in 0..<blobs {
            let a = rng.next() * 2 * .pi
            let d = CGFloat(rng.next()) * radius * 0.55
            let p = CGPoint(x: center.x + cos(a) * d, y: center.y + sin(a) * d)
            let s = radius * CGFloat(wispy ? 0.25 + rng.next() * 0.3 : 0.5 + rng.next() * 0.5)
            layer.fill(Path(ellipseIn: CGRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s)),
                       with: .color(tint.opacity(wispy ? 0.35 : 0.5)))
        }
        // Embedded stars.
        for _ in 0..<4 {
            let a = rng.next() * 2 * .pi
            let d = CGFloat(rng.next()) * radius * 0.6
            let p = CGPoint(x: center.x + cos(a) * d, y: center.y + sin(a) * d)
            context.fill(Path(ellipseIn: CGRect(x: p.x - 1, y: p.y - 1, width: 2, height: 2)), with: .color(.white))
        }
    }

    private func drawPlanetary(_ context: inout GraphicsContext, center: CGPoint, radius: CGFloat, tint: Color) {
        // Planetaries show real color; keep the teal/blue.
        let r = max(radius, 6)
        if r > 12 {
            let rect = CGRect(x: center.x - r * 0.7, y: center.y - r * 0.7, width: r * 1.4, height: r * 1.4)
            var glow = context
            glow.addFilter(.blur(radius: r * 0.14))
            glow.stroke(Path(ellipseIn: rect), with: .color(tint.opacity(0.95)), lineWidth: r * 0.28)
        } else {
            context.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)),
                         with: .radialGradient(Gradient(colors: [tint, tint.opacity(0)]),
                                               center: center, startRadius: 0, endRadius: r))
        }
        context.fill(Path(ellipseIn: CGRect(x: center.x - 1.3, y: center.y - 1.3, width: 2.6, height: 2.6)),
                     with: .color(.white))
    }

    private func drawGlobular(_ context: inout GraphicsContext, center: CGPoint, radius: CGFloat, tint: Color) {
        // Soft unresolved core.
        var glow = context
        glow.addFilter(.blur(radius: radius * 0.3))
        glow.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)),
                  with: .radialGradient(Gradient(colors: [tint.opacity(0.85), tint.opacity(0)]),
                                        center: center, startRadius: 0, endRadius: radius))
        // Resolution grows with aperture and magnification.
        let resolvable = Int(min(160, max(20, (optics.apertureLimitingMagnitude - 6) * 18 + optics.magnification * 0.4)))
        var rng = makeRNG(salt: "glob")
        for _ in 0..<resolvable {
            let a = rng.next() * 2 * .pi
            let dist = CGFloat(rng.next() * rng.next())   // concentrated toward the core
            let p = CGPoint(x: center.x + cos(a) * dist * radius, y: center.y + sin(a) * dist * radius)
            let sr = CGFloat(0.7 + rng.next() * 0.8)
            context.fill(Path(ellipseIn: CGRect(x: p.x - sr, y: p.y - sr, width: sr * 2, height: sr * 2)),
                         with: .color(.white.opacity(0.85)))
        }
    }

    private func drawOpenCluster(_ context: inout GraphicsContext, center: CGPoint, radius: CGFloat, count: Int) {
        var rng = makeRNG(salt: "open")
        for _ in 0..<count {
            let a = rng.next() * 2 * .pi
            let dist = CGFloat(sqrt(rng.next()))
            let p = CGPoint(x: center.x + cos(a) * dist * radius, y: center.y + sin(a) * dist * radius)
            let bright = rng.next()
            let sr = CGFloat(0.8 + bright * bright * 2.0)
            var tint = Color.white
            if rng.next() > 0.85 { tint = Color(red: 0.8, green: 0.85, blue: 1.0) }
            context.fill(Path(ellipseIn: CGRect(x: p.x - sr, y: p.y - sr, width: sr * 2, height: sr * 2)),
                         with: .color(tint.opacity(0.5 + bright * 0.5)))
        }
    }

    // MARK: Star

    private func drawStar(_ context: inout GraphicsContext, center: CGPoint, colorIndex: Double, dim: Double) {
        let tint = AstroPalette.star(colorIndexBV: colorIndex)
        let r: CGFloat = 4
        context.fill(Path(ellipseIn: CGRect(x: center.x - r * 2.2, y: center.y - r * 2.2,
                                            width: r * 4.4, height: r * 4.4)),
                     with: .radialGradient(Gradient(colors: [tint.opacity(0.9 * dim), tint.opacity(0)]),
                                           center: center, startRadius: 0, endRadius: r * 2.2))
        context.fill(Path(ellipseIn: CGRect(x: center.x - r * 0.6, y: center.y - r * 0.6,
                                            width: r * 1.2, height: r * 1.2)), with: .color(.white))
    }

    // MARK: Color helper

    private func mix(_ a: Color, _ b: Color, _ t: Double) -> Color { a.mix(with: b, by: t) }
}

/// Small deterministic PRNG so each object renders identically every launch.
private struct SeededRNG {
    var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(1 << 53)
    }
}
