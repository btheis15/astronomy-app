// Generates the AstroSky app icon (1024×1024 PNG) with CoreGraphics.
// Run: swift Scripts/generate_appicon.swift
// Output: AstroSky/Assets.xcassets/AppIcon.appiconset/AppIcon.png
//
// Design: a deep-space gradient, a soft nebula glow, a scatter of stars, and a
// glowing ringed planet — the same motif as the in-app Saturn glyph.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let S = 1024
let space = CGColorSpaceCreateDeviceRGB()
// Opaque context (no alpha channel) — App Store icons must not be transparent.
// Semi-transparent fills still composite correctly against the drawn background.
guard let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8,
                          bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fatalError("Could not create context")
}

// Work in top-left origin coordinates (like UIKit).
ctx.translateBy(x: 0, y: CGFloat(S))
ctx.scaleBy(x: 1, y: -1)

func color(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat(r), CGFloat(g), CGFloat(b), CGFloat(a)])!
}

let full = CGRect(x: 0, y: 0, width: S, height: S)

// MARK: Background — deep vertical gradient.
let bg = CGGradient(colorsSpace: space,
                    colors: [color(0.09, 0.12, 0.28),
                             color(0.04, 0.05, 0.13),
                             color(0.02, 0.02, 0.06)] as CFArray,
                    locations: [0, 0.55, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: 0),
                       end: CGPoint(x: 0, y: S), options: [])

let planetCenter = CGPoint(x: 512, y: 470)

// MARK: Nebula glow behind the planet.
let nebula = CGGradient(colorsSpace: space,
                        colors: [color(0.35, 0.28, 0.70, 0.55),
                                 color(0.20, 0.20, 0.55, 0.20),
                                 color(0.0, 0.0, 0.0, 0.0)] as CFArray,
                        locations: [0, 0.5, 1])!
ctx.drawRadialGradient(nebula, startCenter: planetCenter, startRadius: 0,
                       endCenter: planetCenter, endRadius: 560, options: [])

// MARK: Stars (deterministic xorshift so the icon is reproducible).
var seed: UInt64 = 88172645463325252
func rnd() -> Double {
    seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
    return Double(seed % 1_000_000) / 1_000_000.0
}
for _ in 0..<150 {
    let x = rnd() * Double(S)
    let y = rnd() * Double(S)
    let radius = 0.6 + rnd() * 2.2
    let alpha = 0.25 + rnd() * 0.75
    // Faint bluish-white twinkle.
    let warm = rnd() > 0.85
    ctx.setFillColor(warm ? color(1.0, 0.9, 0.75, alpha) : color(0.9, 0.94, 1.0, alpha))
    ctx.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
}

// A few brighter hero stars with a soft halo.
for p in [CGPoint(x: 200, y: 240), CGPoint(x: 820, y: 300), CGPoint(x: 730, y: 760)] {
    let halo = CGGradient(colorsSpace: space,
                          colors: [color(1, 1, 1, 0.9), color(0.7, 0.8, 1, 0.0)] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(halo, startCenter: p, startRadius: 0,
                           endCenter: p, endRadius: 26, options: [])
}

// MARK: Ringed planet.
let planetRadius: CGFloat = 200
let tilt = CGFloat(-22 * Double.pi / 180)
let ringOuter = (rx: CGFloat(410), ry: CGFloat(138))
let ringInner = (rx: CGFloat(268), ry: CGFloat(90))

let ringGradient = CGGradient(colorsSpace: space,
                              colors: [color(0.90, 0.80, 0.55, 0.0),
                                       color(0.96, 0.88, 0.66, 0.95),
                                       color(1.0, 0.95, 0.80, 1.0),
                                       color(0.96, 0.88, 0.66, 0.95),
                                       color(0.90, 0.80, 0.55, 0.0)] as CFArray,
                              locations: [0.0, 0.28, 0.5, 0.72, 1.0])!

func drawRingHalf(front: Bool) {
    ctx.saveGState()
    ctx.translateBy(x: planetCenter.x, y: planetCenter.y)
    ctx.rotate(by: tilt)
    // Keep only the near (front, y>0) or far (back, y<0) half.
    let halfRect = CGRect(x: -2000, y: front ? 0 : -2000, width: 4000, height: 2000)
    ctx.clip(to: halfRect)
    // Annulus (even-odd) clip.
    let path = CGMutablePath()
    path.addEllipse(in: CGRect(x: -ringOuter.rx, y: -ringOuter.ry,
                               width: ringOuter.rx * 2, height: ringOuter.ry * 2))
    path.addEllipse(in: CGRect(x: -ringInner.rx, y: -ringInner.ry,
                               width: ringInner.rx * 2, height: ringInner.ry * 2))
    ctx.addPath(path)
    ctx.clip(using: .evenOdd)
    ctx.drawLinearGradient(ringGradient,
                           start: CGPoint(x: -ringOuter.rx, y: 0),
                           end: CGPoint(x: ringOuter.rx, y: 0),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

// Back half of the ring (behind the disk).
drawRingHalf(front: false)

// Planet sphere: warm shaded gold with a top-left highlight.
let sphere = CGGradient(colorsSpace: space,
                        colors: [color(0.99, 0.93, 0.72),
                                 color(0.86, 0.68, 0.38),
                                 color(0.52, 0.34, 0.16)] as CFArray,
                        locations: [0, 0.55, 1])!
let hi = CGPoint(x: planetCenter.x - planetRadius * 0.33, y: planetCenter.y - planetRadius * 0.33)
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: planetCenter.x - planetRadius, y: planetCenter.y - planetRadius,
                          width: planetRadius * 2, height: planetRadius * 2))
ctx.clip()
ctx.drawRadialGradient(sphere, startCenter: hi, startRadius: 0,
                       endCenter: planetCenter, endRadius: planetRadius * 1.15, options: [])
// Subtle banding.
ctx.setBlendMode(.softLight)
for (dy, a) in [(-0.28, 0.30), (-0.05, 0.22), (0.22, 0.30), (0.42, 0.20)] as [(Double, Double)] {
    ctx.setFillColor(color(0.3, 0.2, 0.1, a))
    let y = planetCenter.y + CGFloat(dy) * planetRadius
    ctx.fill(CGRect(x: planetCenter.x - planetRadius, y: y, width: planetRadius * 2, height: planetRadius * 0.10))
}
ctx.setBlendMode(.normal)
ctx.restoreGState()

// Soft terminator shadow on the lower-right for depth.
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: planetCenter.x - planetRadius, y: planetCenter.y - planetRadius,
                          width: planetRadius * 2, height: planetRadius * 2))
ctx.clip()
let shadow = CGGradient(colorsSpace: space,
                        colors: [color(0, 0, 0, 0.0), color(0, 0, 0, 0.45)] as CFArray,
                        locations: [0, 1])!
let sc = CGPoint(x: planetCenter.x + planetRadius * 0.35, y: planetCenter.y + planetRadius * 0.35)
ctx.drawRadialGradient(shadow, startCenter: sc, startRadius: planetRadius * 0.2,
                       endCenter: sc, endRadius: planetRadius * 1.5, options: [])
ctx.restoreGState()

// Front half of the ring (over the disk).
drawRingHalf(front: true)

// MARK: Write PNG.
guard let image = ctx.makeImage() else { fatalError("makeImage failed") }
let outURL = URL(fileURLWithPath: "AstroSky/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("Could not create destination")
}
CGImageDestinationAddImage(dest, image, nil)
if CGImageDestinationFinalize(dest) {
    print("Wrote \(outURL.path)")
} else {
    fatalError("Could not write PNG")
}
