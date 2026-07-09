//
//  EyepiecePreviewView.swift
//  AstroSky
//
//  A simulated eyepiece field: the circular view with the object drawn to
//  scale against the true field of view, type-appropriate, and dimmed for the
//  observer's Bortle sky (clear-night assumption).
//

import SwiftUI

struct EyepiecePreviewView: View {
    let object: any CelestialObject
    let optics: OpticsResult
    let angularSizeRadians: Double?
    let bortleClass: Int

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

            // Sky background: darker at low Bortle, a faint glow at high Bortle.
            let glow = Double(bortleClass - 1) / 8.0
            let sky = Color(red: 0.02 + glow * 0.12, green: 0.02 + glow * 0.09, blue: 0.05 + glow * 0.10)
            context.fill(Path(ellipseIn: fieldRect), with: .color(sky))

            // Object dimming with light pollution.
            let dim = 1.0 - glow * 0.55

            var inner = context
            inner.clip(to: Path(ellipseIn: fieldRect))
            drawObject(&inner, center: center, fieldDiameter: diameter, dim: dim)

            // Field stop ring.
            context.stroke(Path(ellipseIn: fieldRect), with: .color(.gray.opacity(0.6)), lineWidth: 2)
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

    private func drawObject(_ context: inout GraphicsContext, center: CGPoint,
                            fieldDiameter: CGFloat, dim: Double) {
        // Sun gets a warning treatment, not a pretty disk.
        if object.kind == .sun {
            let r = fieldDiameter * 0.2
            context.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)),
                         with: .color(.orange))
            context.draw(Text("☀︎ Use a solar filter").font(.caption.bold()).foregroundStyle(.red),
                         at: CGPoint(x: center.x, y: center.y + r + 16))
            return
        }

        let objectPixels = CGFloat(min(1.0, fillFraction)) * fieldDiameter
        guard let deepSky = object as? DeepSkyObject else {
            drawSolarOrPoint(&context, center: center, diameter: max(objectPixels, 6), dim: dim)
            return
        }
        let radius = max(objectPixels / 2, 3)
        let color = Color(uiColor: SkySceneBuilder.deepSkyColor(for: deepSky.type)).opacity(dim)

        switch deepSky.type {
        case .galaxy:
            let ratio = DeepSkySizes.axisRatio(for: deepSky)
            let rect = CGRect(x: center.x - radius, y: center.y - radius * ratio,
                              width: 2 * radius, height: 2 * radius * ratio)
            context.fill(Path(ellipseIn: rect), with: .radialGradient(
                Gradient(colors: [color, color.opacity(0)]),
                center: center, startRadius: 0, endRadius: radius))
        case .nebula, .supernovaRemnant:
            context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                width: 2 * radius, height: 2 * radius)),
                         with: .radialGradient(Gradient(colors: [color.opacity(0.7), color.opacity(0)]),
                                               center: center, startRadius: 0, endRadius: radius))
        case .planetaryNebula:
            context.stroke(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                  width: 2 * radius, height: 2 * radius)),
                           with: .color(color), lineWidth: max(2, radius * 0.3))
        case .globularCluster:
            drawCluster(&context, center: center, radius: radius, count: 90, concentrated: true, color: color)
        case .openCluster, .asterism, .starCloud:
            drawCluster(&context, center: center, radius: radius, count: 40, concentrated: false, color: color)
        }
    }

    private func drawSolarOrPoint(_ context: inout GraphicsContext, center: CGPoint,
                                  diameter: CGFloat, dim: Double) {
        if object.kind == .planet || object.kind == .moon {
            let color: Color = object.kind == .moon ? .white : .yellow
            context.fill(Path(ellipseIn: CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2,
                                                width: diameter, height: diameter)),
                         with: .color(color.opacity(dim)))
        } else {
            // Star / point source: a small glow.
            let r: CGFloat = 5
            context.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)),
                         with: .radialGradient(Gradient(colors: [.white, .white.opacity(0)]),
                                               center: center, startRadius: 0, endRadius: r * 2))
        }
    }

    private func drawCluster(_ context: inout GraphicsContext, center: CGPoint, radius: CGFloat,
                             count: Int, concentrated: Bool, color: Color) {
        var seed = UInt64(bitPattern: Int64(object.id.hashValue))
        func next() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 11) / Double(1 << 53)
        }
        for _ in 0..<count {
            let angle = next() * 2 * .pi
            var dist = next()
            if concentrated { dist *= dist }   // bias toward the core
            let x = center.x + CGFloat(cos(angle) * dist) * radius
            let y = center.y + CGFloat(sin(angle) * dist) * radius
            let dot = CGRect(x: x - 1.2, y: y - 1.2, width: 2.4, height: 2.4)
            context.fill(Path(ellipseIn: dot), with: .color(.white.opacity(0.9)))
        }
        _ = color
    }
}
