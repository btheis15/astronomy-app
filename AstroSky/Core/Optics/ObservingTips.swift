//
//  ObservingTips.swift
//  AstroSky
//
//  Practical, plain-language tips for seeing an object well — generic per
//  object type, with hand-written notes for famous targets and magnification
//  advice from the current optics.
//

import Foundation

enum ObservingTips {
    static func tips(for object: any CelestialObject, optics: OpticsResult?) -> [String] {
        var tips: [String] = []

        // Per-object famous notes.
        if let specific = notable[object.id] { tips.append(specific) }

        // Per-type generic advice.
        switch object.kind {
        case .deepSky:
            if let deepSky = object as? DeepSkyObject {
                switch deepSky.type {
                case .galaxy:
                    tips.append("Use averted vision — look slightly to the side to catch faint detail.")
                case .nebula, .supernovaRemnant:
                    tips.append("A UHC or OIII filter boosts contrast against light pollution.")
                case .planetaryNebula:
                    tips.append("Small and bright — crank up the magnification to see its shape.")
                case .openCluster, .asterism, .starCloud:
                    tips.append("Best at low power so the whole group fits in the field.")
                case .globularCluster:
                    tips.append("More aperture and higher power resolves the outer stars into pinpoints.")
                }
            }
        case .planet:
            tips.append("Wait for steady air and let the scope cool — planets reward patience at high power.")
        case .moon:
            tips.append("The terminator (day/night line) shows the most dramatic crater shadows.")
        case .sun:
            tips.append("⚠️ NEVER point a telescope at the Sun without a certified solar filter over the front.")
        default:
            break
        }

        // Magnification hint from the optics.
        if let optics, optics.magnification > 0 {
            if optics.exitPupilMM < 0.5 {
                tips.append("Your exit pupil is tiny (\(String(format: "%.1f", optics.exitPupilMM)) mm) — try a longer eyepiece for a brighter image.")
            } else if optics.exitPupilMM > 7 {
                tips.append("Exit pupil over 7 mm wastes light — a shorter eyepiece will frame it better.")
            }
        }
        return tips
    }

    private static let notable: [String: String] = [
        "m031": "Look for the dust lane and the two companion galaxies (M32 and M110) nearby.",
        "m042": "The four stars of the Trapezium sit in the bright core — bump up the power to split them.",
        "m013": "A glorious globular — at higher power the edges resolve into a swarm of stars.",
        "m045": "The Pleiades overflow most eyepieces — use your lowest power and enjoy the blue sparkle.",
        "m057": "The Ring Nebula's smoke-ring shape needs ~100× and a steady night.",
        "planet.saturn": "The rings show even at 50×; look for the Cassini Division at higher power.",
        "planet.jupiter": "The four Galilean moons shift nightly; the cloud belts appear in moments of steady air.",
        "planet.mars": "Small and tricky — wait for opposition and steady seeing to glimpse surface markings.",
        "moon": "First-quarter and last-quarter phases show the best shadow relief along the terminator.",
    ]
}
