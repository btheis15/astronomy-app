//
//  MountGuidance.swift
//  AstroSky
//
//  Mount-type-specific setup and "how to find this object" instructions.
//

import Foundation

enum MountType: String, Codable, CaseIterable, Sendable, Identifiable {
    case altAzimuth
    case equatorial
    case goTo

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .altAzimuth: "Alt-azimuth / Dobsonian"
        case .equatorial: "Equatorial (EQ)"
        case .goTo: "GoTo / computerized"
        }
    }

    var beginnerDescription: String {
        switch self {
        case .altAzimuth: "Swivels up/down and left/right — the simplest kind. Includes most Dobsonians and tabletop scopes."
        case .equatorial: "Has a tilted axis you align to the celestial pole so it can track the sky with one motion."
        case .goTo: "A motorized mount you align to a few stars, then tell it what to point at."
        }
    }
}

struct FinderStep: Identifiable, Sendable {
    let id = UUID()
    let text: String
    let systemImage: String
}

struct MountGuidance: Sendable {
    var setupSteps: [FinderStep]
    var findSteps: [FinderStep]
    var settingCircles: [(label: String, value: String)]
    var alignmentStars: [Star]
}

enum MountGuidanceGenerator {
    static func guidance(mount: MountType,
                         object: any CelestialObject,
                         julianDate jd: Double,
                         observer: Observer,
                         catalog: SkyCatalog) -> MountGuidance {
        let position = object.skyPosition(julianDate: jd, observer: observer)
        let horizontal = position.horizontal
        let ofDate = CoordinateTransforms.precessFromJ2000(position.equatorialJ2000, julianDate: jd)

        switch mount {
        case .altAzimuth:
            return MountGuidance(
                setupSteps: [
                    FinderStep(text: "Set the scope on a level, stable spot with a clear view of the target's direction.", systemImage: "square.3.layers.3d"),
                    FinderStep(text: "Align your finder scope on a distant object by day so it matches the main view.", systemImage: "scope"),
                ],
                findSteps: [
                    FinderStep(text: "Face \(AstroFormat.azimuth(horizontal)).", systemImage: "safari"),
                    FinderStep(text: "Tilt the tube to \(AstroFormat.degrees(horizontal.altitude)) above the horizon.", systemImage: "arrow.up.and.down"),
                    FinderStep(text: "Center it in the finder, then look through a low-power eyepiece and sweep gently.", systemImage: "magnifyingglass"),
                ],
                settingCircles: [
                    ("Altitude", AstroFormat.degrees(horizontal.altitude)),
                    ("Azimuth", AstroFormat.azimuth(horizontal)),
                ],
                alignmentStars: [])

        case .equatorial:
            let lst = AstroTime.localApparentSiderealTime(julianDate: jd, longitude: observer.longitude)
            let hourAngle = AstroMath.signedRadians(lst - ofDate.rightAscension)
            let haHours = hourAngle * AstroMath.radToHours
            let haText = String(format: "%@%.1fh %@", haHours < 0 ? "−" : "", abs(haHours),
                                haHours < 0 ? "(east)" : "(west)")
            return MountGuidance(
                setupSteps: [
                    FinderStep(text: "Level the tripod and set the latitude scale to \(String(format: "%.0f°", observer.latitudeDegrees)).", systemImage: "ruler"),
                    FinderStep(text: "Point the polar (RA) axis at Polaris / the celestial pole to polar-align.", systemImage: "location.north.line"),
                ],
                findSteps: [
                    FinderStep(text: "Set the declination circle to \(AstroFormat.declination(ofDate)).", systemImage: "arrow.up.and.down"),
                    FinderStep(text: "Set the RA / hour-angle circle to \(haText).", systemImage: "clock.arrow.circlepath"),
                    FinderStep(text: "Lock the axes and confirm in the finder.", systemImage: "scope"),
                ],
                settingCircles: [
                    ("Right ascension", AstroFormat.rightAscension(ofDate)),
                    ("Declination", AstroFormat.declination(ofDate)),
                    ("Hour angle", haText),
                ],
                alignmentStars: [])

        case .goTo:
            let stars = catalog.brightStarsAbove(altitudeDegrees: 20, julianDate: jd, observer: observer, limit: 6)
            return MountGuidance(
                setupSteps: [
                    FinderStep(text: "Level the mount and complete its star-alignment routine first.", systemImage: "checklist"),
                    FinderStep(text: "Use bright stars currently high up (below) as alignment references.", systemImage: "star"),
                ],
                findSteps: [
                    FinderStep(text: "Enter Right Ascension \(AstroFormat.rightAscension(object.skyPosition(julianDate: jd, observer: observer).equatorialJ2000)) (J2000).", systemImage: "number"),
                    FinderStep(text: "Enter Declination \(AstroFormat.declination(object.skyPosition(julianDate: jd, observer: observer).equatorialJ2000)) (J2000), then GoTo.", systemImage: "number"),
                ],
                settingCircles: [
                    ("RA (J2000)", AstroFormat.rightAscension(object.skyPosition(julianDate: jd, observer: observer).equatorialJ2000)),
                    ("Dec (J2000)", AstroFormat.declination(object.skyPosition(julianDate: jd, observer: observer).equatorialJ2000)),
                ],
                alignmentStars: stars)
        }
    }
}
