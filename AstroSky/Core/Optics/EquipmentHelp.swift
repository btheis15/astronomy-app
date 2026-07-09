//
//  EquipmentHelp.swift
//  AstroSky
//
//  Beginner-friendly copy and starter presets for the equipment editor, kept
//  in one place so it's easy to review, translate and test.
//

import Foundation

enum EquipmentHelp {
    // Field explanations (what it is · where to find it · why it matters).
    static let scopeFocalLength = "The focal length of your telescope in millimetres — usually printed on the tube or box (e.g. “f=1200mm”). Longer focal length ⇒ more magnification with the same eyepiece."
    static let aperture = "The diameter of the main lens or mirror in millimetres (e.g. “D=200mm”, or 8 inch ≈ 203 mm). Bigger aperture gathers more light, so you see fainter objects."
    static let eyepieceFocalLength = "The number printed on the eyepiece barrel, in millimetres (e.g. “25mm”). Shorter eyepiece ⇒ higher magnification."
    static let apparentFOV = "How wide the eyepiece's view looks, in degrees — from its specs (a basic Plössl is about 52°). Leave the default if you're unsure."

    static let mountIntro = "Pick the kind of mount your telescope sits on so the finder steps match how you actually aim it."

    /// Starter telescopes for one-tap setup.
    static let telescopePresets: [Telescope] = [
        Telescope(name: "60mm refractor", focalLengthMM: 700, apertureMM: 60),
        Telescope(name: "130mm reflector", focalLengthMM: 650, apertureMM: 130),
        Telescope(name: "8-inch Dobsonian", focalLengthMM: 1200, apertureMM: 203),
        Telescope(name: "Maksutov 127", focalLengthMM: 1500, apertureMM: 127),
    ]

    /// Starter eyepieces.
    static let eyepiecePresets: [Eyepiece] = [
        Eyepiece(name: "25mm Plössl", focalLengthMM: 25, apparentFOVDegrees: 52),
        Eyepiece(name: "10mm Plössl", focalLengthMM: 10, apparentFOVDegrees: 52),
        Eyepiece(name: "32mm wide-field", focalLengthMM: 32, apparentFOVDegrees: 56),
        Eyepiece(name: "6mm high-power", focalLengthMM: 6, apparentFOVDegrees: 58),
    ]

    /// Plain-language reading of an exit pupil in millimetres.
    static func exitPupilNote(_ mm: Double) -> String {
        switch mm {
        case ..<0.5: "very high power — dim, only for tight targets"
        case ..<2: "high power — good for planets and small objects"
        case ..<5: "medium power — a comfortable all-rounder"
        case ..<7: "low power — bright, wide views of clusters and nebulae"
        default: "very low power — some light is wasted beyond your eye's pupil"
        }
    }
}
