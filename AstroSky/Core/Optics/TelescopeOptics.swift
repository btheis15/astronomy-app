//
//  TelescopeOptics.swift
//  AstroSky
//
//  Pure telescope optics: combine a telescope and an eyepiece into the numbers
//  that decide what you'll see — magnification, true field of view, exit pupil,
//  resolving power and aperture-limited faintness.
//

import Foundation

struct Telescope: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var focalLengthMM: Double
    var apertureMM: Double

    init(id: UUID = UUID(), name: String, focalLengthMM: Double, apertureMM: Double) {
        self.id = id
        self.name = name
        self.focalLengthMM = focalLengthMM
        self.apertureMM = apertureMM
    }

    /// f-number (focal ratio).
    var focalRatio: Double { apertureMM > 0 ? focalLengthMM / apertureMM : 0 }
}

struct Eyepiece: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var focalLengthMM: Double
    var apparentFOVDegrees: Double

    init(id: UUID = UUID(), name: String, focalLengthMM: Double, apparentFOVDegrees: Double = 52) {
        self.id = id
        self.name = name
        self.focalLengthMM = focalLengthMM
        self.apparentFOVDegrees = apparentFOVDegrees
    }
}

/// The combined result of a telescope + eyepiece (+ sky darkness).
struct OpticsResult: Sendable, Equatable {
    let magnification: Double
    let trueFOVRadians: Double
    let exitPupilMM: Double
    let dawesLimitRadians: Double
    let apertureLimitingMagnitude: Double

    var trueFOVDegrees: Double { trueFOVRadians * AstroMath.radToDeg }
}

enum TelescopeMath {
    static func magnification(scopeFocalMM: Double, eyepieceFocalMM: Double) -> Double {
        eyepieceFocalMM > 0 ? scopeFocalMM / eyepieceFocalMM : 0
    }

    static func trueFOVRadians(apparentFOVDegrees: Double, magnification: Double) -> Double {
        guard magnification > 0 else { return 0 }
        return (apparentFOVDegrees / magnification) * AstroMath.degToRad
    }

    static func exitPupilMM(apertureMM: Double, magnification: Double) -> Double {
        magnification > 0 ? apertureMM / magnification : 0
    }

    /// Dawes' resolving limit: 116″ / aperture(mm), returned in radians.
    static func dawesLimitRadians(apertureMM: Double) -> Double {
        guard apertureMM > 0 else { return 0 }
        return (116.0 / apertureMM) / 3600.0 * AstroMath.degToRad
    }

    /// Faintest star the aperture reaches, ≈ 2.7 + 5·log10(D_mm), reduced by a
    /// light-pollution penalty derived from the Bortle naked-eye limit.
    static func apertureLimitingMagnitude(apertureMM: Double, bortleClass: Int) -> Double {
        guard apertureMM > 0 else { return 0 }
        let base = 2.7 + 5 * log10(apertureMM)
        // Light pollution costs telescopic reach roughly one magnitude per
        // naked-eye magnitude of sky glow relative to a pristine (Bortle 1) sky.
        let nakedEye = 7.5 - Double(bortleClass - 1) * (7.5 - 4.0) / 8.0
        let penalty = 7.5 - nakedEye
        return base - penalty
    }

    /// Fraction of the eyepiece field an object of the given angular size fills.
    static func fractionOfField(objectAngularRadians: Double, trueFOVRadians: Double) -> Double {
        trueFOVRadians > 0 ? objectAngularRadians / trueFOVRadians : 0
    }

    static func result(scope: Telescope, eyepiece: Eyepiece, bortleClass: Int) -> OpticsResult {
        let mag = magnification(scopeFocalMM: scope.focalLengthMM, eyepieceFocalMM: eyepiece.focalLengthMM)
        return OpticsResult(
            magnification: mag,
            trueFOVRadians: trueFOVRadians(apparentFOVDegrees: eyepiece.apparentFOVDegrees, magnification: mag),
            exitPupilMM: exitPupilMM(apertureMM: scope.apertureMM, magnification: mag),
            dawesLimitRadians: dawesLimitRadians(apertureMM: scope.apertureMM),
            apertureLimitingMagnitude: apertureLimitingMagnitude(apertureMM: scope.apertureMM, bortleClass: bortleClass))
    }
}
