//
//  ScaleModelTexture.swift
//  AstroSky
//
//  Textures for the Scale AR bodies: use a bundled 2K map (from
//  Scripts/fetch_textures.sh) when present, otherwise draw a passable
//  procedural equirectangular map so the scene always renders.
//

import RealityKit
import UIKit
import simd

enum ScaleModelTexture {
    static func texture(for body: ScaleBody) -> TextureResource? {
        if let key = body.textureKey, let cgImage = bundledImage(named: key) {
            return try? TextureResource(image: cgImage, withName: key, options: .init(semantic: .color))
        }
        guard let procedural = makeProcedural(for: body) else { return nil }
        return try? TextureResource(image: procedural, withName: "proc_\(body.key)",
                                    options: .init(semantic: .color))
    }

    /// Saturn's ring texture (alpha PNG) if bundled, else nil (tan fallback).
    static func ringTexture() -> TextureResource? {
        guard let cgImage = bundledImage(named: "2k_saturn_ring_alpha") else { return nil }
        return try? TextureResource(image: cgImage, withName: "saturnRing", options: .init(semantic: .color))
    }

    private static func bundledImage(named key: String) -> CGImage? {
        if let image = UIImage(named: key)?.cgImage { return image }
        for ext in ["jpg", "png"] {
            for subdir in [nil, "Textures"] as [String?] {
                if let url = Bundle.main.url(forResource: key, withExtension: ext, subdirectory: subdir),
                   let image = UIImage(contentsOfFile: url.path)?.cgImage {
                    return image
                }
            }
        }
        return nil
    }

    // MARK: Procedural equirectangular maps

    private static let gasGiants: Set<String> = ["jupiter", "saturn", "uranus", "neptune"]

    private static func makeProcedural(for body: ScaleBody) -> CGImage? {
        let width = 1024, height = 512
        let color = UIColor(red: body.tint.x, green: body.tint.y, blue: body.tint.z, alpha: 1)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        let image = renderer.image { context in
            let cg = context.cgContext
            color.setFill()
            cg.fill(CGRect(x: 0, y: 0, width: width, height: height))

            var seed = UInt64(bitPattern: Int64(body.key.hashValue))
            func rand() -> Double {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return Double(seed >> 11) / Double(1 << 53)
            }

            if gasGiants.contains(body.key) {
                // Horizontal banding.
                var y = 0.0
                while y < Double(height) {
                    let bandHeight = 8 + rand() * 26
                    let shade = (rand() - 0.5) * 0.35
                    cg.setFillColor(color.adjustingBrightness(by: shade).cgColor)
                    cg.fill(CGRect(x: 0, y: y, width: Double(width), height: bandHeight))
                    y += bandHeight
                }
            } else {
                // Mottled surface: scattered lighter/darker blotches (craters/terrain).
                for _ in 0..<220 {
                    let r = 4 + rand() * 26
                    let x = rand() * Double(width)
                    let y = rand() * Double(height)
                    let shade = (rand() - 0.5) * 0.4
                    cg.setFillColor(color.adjustingBrightness(by: shade).withAlphaComponent(0.5).cgColor)
                    cg.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
                }
            }
        }
        return image.cgImage
    }
}

private extension UIColor {
    func adjustingBrightness(by delta: Double) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: max(0, min(1, r + delta)),
                       green: max(0, min(1, g + delta)),
                       blue: max(0, min(1, b + delta)), alpha: a)
    }
}
