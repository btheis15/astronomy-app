//
//  TelescopeVisibility.swift
//  AstroSky
//
//  How hard an object is to see with a given scope under a given sky.
//

import Foundation

struct VisibilityAssessment: Sendable {
    enum Verdict: String, Sendable {
        case easy = "Easy"
        case visible = "Visible"
        case challenging = "Challenging"
        case notVisible = "Beyond this scope"

        var systemImage: String {
            switch self {
            case .easy: "eye.fill"
            case .visible: "eye"
            case .challenging: "eye.trianglebadge.exclamationmark"
            case .notVisible: "eye.slash"
            }
        }
    }

    let verdict: Verdict
    let reason: String
    let fillsFieldFraction: Double
}

enum TelescopeVisibility {
    static func assess(object: any CelestialObject,
                       optics: OpticsResult,
                       angularSizeRadians: Double?,
                       bortleClass: Int) -> VisibilityAssessment {
        let fills = angularSizeRadians.map {
            TelescopeMath.fractionOfField(objectAngularRadians: $0, trueFOVRadians: optics.trueFOVRadians)
        } ?? 0

        guard let magnitude = object.magnitude else {
            // Point sources with no magnitude (rare) — assume visible.
            return VisibilityAssessment(verdict: .visible, reason: "Should be within reach.", fillsFieldFraction: fills)
        }

        // Extended low-surface-brightness objects (big faint galaxies/nebulae)
        // are harder than their integrated magnitude suggests.
        var effectiveMagnitude = magnitude
        if let size = angularSizeRadians, let deepSky = object as? DeepSkyObject,
           deepSky.type == .galaxy || deepSky.type == .nebula {
            let arcmin = size * AstroMath.radToDeg * 60
            if arcmin > 10 { effectiveMagnitude += min(2.0, log10(arcmin / 10) * 2.5) }
        }

        let limit = optics.apertureLimitingMagnitude
        let margin = limit - effectiveMagnitude

        let verdict: VisibilityAssessment.Verdict
        let reason: String
        if margin >= 2 {
            verdict = .easy
            reason = "Bright for your \(Int(optics.magnification))× view — an easy target."
        } else if margin >= 0.3 {
            verdict = .visible
            reason = "Within reach of your aperture under a Bortle \(bortleClass) sky."
        } else if margin >= -0.7 {
            verdict = .challenging
            reason = "Near your aperture's limit — try higher power and a darker sky."
        } else {
            verdict = .notVisible
            reason = "Fainter than your aperture reaches under this sky."
        }
        return VisibilityAssessment(verdict: verdict, reason: reason, fillsFieldFraction: fills)
    }
}
