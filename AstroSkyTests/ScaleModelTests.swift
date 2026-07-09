//
//  ScaleModelTests.swift
//  AstroSkyTests
//

import Foundation
import Testing
@testable import AstroSky

struct ScaleModelTests {
    @Test func sceneScaleSizesPrimaryToTarget() {
        let scale = ScaleModelMath.sceneScale(primaryRadiusKm: 6378.1, targetMeters: 0.15)
        #expect(abs(ScaleModelMath.bodyRadiusMeters(km: 6378.1, scale: scale) - 0.15) < 1e-6)
    }

    @Test func sizesStayProportional() {
        // At a planet-system scale, Jupiter/Earth radius ratio (~11.2) is preserved.
        let scale = ScaleModelMath.sceneScale(primaryRadiusKm: 6378.1, targetMeters: 0.15)
        let jupiter = ScaleModelMath.bodyRadiusMeters(km: 71_492, scale: scale)
        let earth = ScaleModelMath.bodyRadiusMeters(km: 6378.1, scale: scale)
        #expect(abs(jupiter / earth - 71_492 / 6378.1) < 0.05)
    }

    @Test func compressedDistancesIncrease() {
        let primary = 0.15
        let scale = 1e-6
        var last = 0.0
        for i in 0..<4 {
            let d = ScaleModelMath.distanceMeters(orbitKm: 100_000, primaryRadiusMeters: primary,
                                                  scale: scale, mode: .fit,
                                                  satelliteIndex: i, satelliteCount: 4)
            #expect(d > last)
            last = d
        }
    }

    @Test func trueScaleUsesRealOrbit() {
        let d = ScaleModelMath.distanceMeters(orbitKm: 384_400, primaryRadiusMeters: 0.15,
                                              scale: 1e-6, mode: .trueScale,
                                              satelliteIndex: 0, satelliteCount: 1)
        #expect(abs(d - 0.3844) < 1e-6)
    }

    @Test func catalogScenesArePopulated() {
        #expect(ScaleModelCatalog.bodies(for: .earthMoon).count == 2)
        let jupiter = ScaleModelCatalog.bodies(for: .planet(.jupiter))
        #expect(jupiter.count == 5)                        // Jupiter + 4 Galileans
        #expect(jupiter.first?.key == "jupiter")
        #expect(ScaleModelCatalog.bodies(for: .solarSystem).count == 8)   // Sun + 7 visible
        #expect(ScaleModelCatalog.bodies(for: .galaxy).count == 1)
    }

    @Test func ganymedeLargerThanEuropa() {
        let jupiter = ScaleModelCatalog.bodies(for: .planet(.jupiter))
        let ganymede = jupiter.first { $0.key == "ganymede" }!
        let europa = jupiter.first { $0.key == "europa" }!
        #expect(ganymede.radiusKm > europa.radiusKm)
    }

    @Test func saturnHasRings() {
        let saturn = ScaleModelCatalog.bodies(for: .planet(.saturn)).first!
        #expect(saturn.hasRings)
    }
}
