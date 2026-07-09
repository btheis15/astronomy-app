//
//  TelescopeTests.swift
//  AstroSkyTests
//

import Foundation
import Testing
@testable import AstroSky

struct TelescopeOpticsTests {
    private let scope = Telescope(name: "8\" Dob", focalLengthMM: 1200, apertureMM: 203)
    private let ep25 = Eyepiece(name: "25mm", focalLengthMM: 25, apparentFOVDegrees: 52)

    @Test func magnificationAndField() {
        let optics = TelescopeMath.result(scope: scope, eyepiece: ep25, bortleClass: 4)
        #expect(abs(optics.magnification - 48) < 0.5)
        #expect(abs(optics.trueFOVDegrees - (52.0 / 48.0)) < 0.02)
        #expect(abs(optics.exitPupilMM - (203.0 / 48.0)) < 0.1)
    }

    @Test func dawesLimit() {
        let arcsec = TelescopeMath.dawesLimitRadians(apertureMM: 116) * AstroMath.radToDeg * 3600
        #expect(abs(arcsec - 1.0) < 0.01)   // 116/116 = 1.0"
    }

    @Test func limitingMagnitudeDarkerSkyReachesFainter() {
        let dark = TelescopeMath.apertureLimitingMagnitude(apertureMM: 200, bortleClass: 1)
        let bright = TelescopeMath.apertureLimitingMagnitude(apertureMM: 200, bortleClass: 9)
        #expect(dark > bright)
        #expect(dark > 12 && dark < 15)     // ~14.2 base at Bortle 1
    }

    @Test func fractionOfField() {
        let tfov = 1.0 * AstroMath.degToRad
        #expect(abs(TelescopeMath.fractionOfField(objectAngularRadians: tfov, trueFOVRadians: tfov) - 1.0) < 1e-9)
        #expect(abs(TelescopeMath.fractionOfField(objectAngularRadians: tfov / 2, trueFOVRadians: tfov) - 0.5) < 1e-9)
    }
}

struct TelescopeVisibilityTests {
    private let bigScope = Telescope(name: "Big", focalLengthMM: 1200, apertureMM: 250)
    private let ep = Eyepiece(name: "10mm", focalLengthMM: 10)

    @Test func brightObjectIsEasy() {
        let optics = TelescopeMath.result(scope: bigScope, eyepiece: ep, bortleClass: 3)
        // The Pleiades (M45, mag ~1.6).
        let m45 = MessierCatalog.objects.first { $0.catalogNumber == 45 }!
        let size = AngularSizeSource.angularSizeRadians(for: m45, julianDate: AstroTime.j2000)
        let verdict = TelescopeVisibility.assess(object: m45, optics: optics,
                                                 angularSizeRadians: size, bortleClass: 3).verdict
        #expect(verdict == .easy || verdict == .visible)
    }

    @Test func faintObjectBeyondSmallScope() {
        let tiny = Telescope(name: "Tiny", focalLengthMM: 400, apertureMM: 50)
        let optics = TelescopeMath.result(scope: tiny, eyepiece: ep, bortleClass: 8)
        // A faint galaxy (M110, mag ~8) in a bright sky through a 50mm scope.
        let m110 = MessierCatalog.objects.first { $0.catalogNumber == 110 }!
        let size = AngularSizeSource.angularSizeRadians(for: m110, julianDate: AstroTime.j2000)
        let verdict = TelescopeVisibility.assess(object: m110, optics: optics,
                                                 angularSizeRadians: size, bortleClass: 8).verdict
        #expect(verdict == .challenging || verdict == .notVisible)
    }
}

struct EquipmentAndSizeTests {
    @Test func equipmentRoundTrips() throws {
        var library = EquipmentLibrary.empty
        let scope = Telescope(name: "S", focalLengthMM: 1000, apertureMM: 200)
        library.telescopes = [scope]
        library.activeTelescopeID = scope.id
        library.mountType = .equatorial
        let data = try JSONEncoder().encode(library)
        let decoded = try JSONDecoder().decode(EquipmentLibrary.self, from: data)
        #expect(decoded.activeTelescope?.name == "S")
        #expect(decoded.mountType == .equatorial)
        #expect(decoded.opticsResult(bortleClass: 4) == nil)   // no eyepiece yet
    }

    @Test func andromedaHasRealSize() {
        let m31 = MessierCatalog.objects.first { $0.catalogNumber == 31 }!
        #expect(DeepSkySizes.angularSizeArcmin(for: m31) == 178)
    }

    @Test func unknownDeepSkyUsesFallback() {
        #expect(DeepSkySizes.fallbackArcmin(type: .galaxy, magnitude: 11) > 0)
    }

    @Test func presetsAreValid() {
        for scope in EquipmentHelp.telescopePresets {
            #expect(scope.focalLengthMM > 0 && scope.apertureMM > 0)
        }
        for eyepiece in EquipmentHelp.eyepiecePresets {
            #expect(eyepiece.focalLengthMM > 0 && eyepiece.apparentFOVDegrees > 20)
        }
    }
}
