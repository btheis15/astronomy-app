//
//  NorthCalibratorTests.swift
//  AstroSkyTests
//
//  Exercises the compass-fusion math in NorthCalibrator without requiring
//  a physical device or live ARKit session. All inputs are hand-crafted
//  camera transforms and synthetic CLHeading values.
//

import Testing
import simd
@testable import AstroSky

// Camera-transform helpers
// ARKit camera forward = −columns.2; azimuth = atan2(fwdX, −fwdZ).
// Identity → fwdX=0, fwdZ=−1 → azimuth 0 (North in ARKit space).

@MainActor
struct NorthCalibratorTests {

    // Camera facing ARKit North (−Z): atan2(0, 1) = 0.
    private let northFacingCamera = matrix_identity_float4x4

    // Camera facing ARKit East (+X): columns.2 = (−1,0,0,0) → fwdX=1, fwdZ=0 → atan2(1,0)=π/2.
    private var eastFacingCamera: simd_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.2 = simd_float4(-1, 0, 0, 0)
        return m
    }

    // MARK: Gating tests

    @Test func invalidHeadingIsIgnored() {
        let cal = NorthCalibrator()
        cal.step(cameraTransform: northFacingCamera, trueHeadingDeg: -1,
                 headingAccuracy: 5, dt: 0.016)
        #expect(cal.currentOffset == 0)
    }

    @Test func inaccurateHeadingIsIgnored() {
        let cal = NorthCalibrator()
        // 60° accuracy exceeds the 30° gate.
        cal.step(cameraTransform: northFacingCamera, trueHeadingDeg: 0,
                 headingAccuracy: 60, dt: 0.016)
        #expect(cal.currentOffset == 0)
    }

    @Test func nilAccuracyIsIgnored() {
        let cal = NorthCalibrator()
        cal.step(cameraTransform: northFacingCamera, trueHeadingDeg: 0,
                 headingAccuracy: nil, dt: 0.016)
        #expect(cal.currentOffset == 0)
    }

    // MARK: Acquiring regime

    @Test func acquiringModeSnapsDirectly() {
        let cal = NorthCalibrator()
        let maxPerFrame: Float = (Float.pi / 90) * 0.016  // max one slew step
        // In acquiring mode, currentOffset snaps to the circular mean — not capped by slew rate.
        cal.step(cameraTransform: eastFacingCamera, trueHeadingDeg: 0,
                 headingAccuracy: 5, dt: 0.016)
        #expect(abs(cal.currentOffset) > maxPerFrame)
    }

    @Test func coldStartConvergesWithinFiveSamples() {
        let cal = NorthCalibrator()
        // Five acquiring samples should put the offset clearly in the correct hemisphere.
        for _ in 0..<5 {
            cal.step(cameraTransform: eastFacingCamera, trueHeadingDeg: 0,
                     headingAccuracy: 5, dt: 0.016)
        }
        // Target = 0 − π/2 = −π/2; expect within 10° of −90°.
        #expect(cal.currentOffset < Float(-10.0 * Double.pi / 180))
    }

    @Test func resetReAcquires() {
        let cal = NorthCalibrator()
        // First run: converge with east camera (target = −π/2).
        for _ in 0..<200 {
            cal.step(cameraTransform: eastFacingCamera, trueHeadingDeg: 0,
                     headingAccuracy: 5, dt: 1.0)
        }
        #expect(cal.currentOffset < -Float.pi / 4)

        // After reset, five north-camera acquiring samples should return near 0.
        cal.reset()
        for _ in 0..<5 {
            cal.step(cameraTransform: northFacingCamera, trueHeadingDeg: 0,
                     headingAccuracy: 5, dt: 0.016)
        }
        #expect(abs(cal.currentOffset) < Float(5.0 * Double.pi / 180))  // < 5°
    }

    // MARK: Convergence tests (tracking regime)

    @Test func northCameraWithNorthHeadingConvergesToZero() {
        let cal = NorthCalibrator()
        // Camera facing North (azimuth 0) + heading 0° → correction 0 − 0 = 0.
        for _ in 0..<400 {
            cal.step(cameraTransform: northFacingCamera, trueHeadingDeg: 0,
                     headingAccuracy: 5, dt: 0.016)
        }
        #expect(abs(cal.currentOffset) < Float(3.0 * Double.pi / 180))   // < 3°
    }

    @Test func eastCameraWithNorthHeadingConvergesToNegativeQuarterPi() {
        let cal = NorthCalibrator()
        // Camera facing East (azimuth π/2), heading 0° → correction = 0 − π/2 = −π/2.
        // Use dt=1s so the 2°/s slew closes the 90° gap in ~45 steps (not 2800).
        for _ in 0..<200 {
            cal.step(cameraTransform: eastFacingCamera, trueHeadingDeg: 0,
                     headingAccuracy: 5, dt: 1.0)
        }
        #expect(abs(cal.currentOffset + Float.pi / 2) < Float(2.0 * Double.pi / 180))  // < 2°
    }

    @Test func wraparoundConvergesToShortPath() {
        let cal = NorthCalibrator()
        // Camera pointing 1° east of ARKit North (arkitAz ≈ 1°), heading 359°.
        // rawDelta = 359° − 1° = 358° → normalized → −2° (short way, not +358°).
        let azRad = Float(1.0 * Double.pi / 180)
        var nearNorthCamera = matrix_identity_float4x4
        nearNorthCamera.columns.2 = simd_float4(-sin(azRad), 0, cos(azRad), 0)
        for _ in 0..<200 {
            cal.step(cameraTransform: nearNorthCamera, trueHeadingDeg: 359,
                     headingAccuracy: 5, dt: 1.0)
        }
        let expectedRad = Float(-2.0 * Double.pi / 180)
        #expect(abs(cal.currentOffset - expectedRad) < Float(2.0 * Double.pi / 180))  // < 2°
    }

    // MARK: Slew-rate cap (tracking regime only)

    @Test func slewRateCapPreventsInstantJumpInTrackingMode() {
        let cal = NorthCalibrator()
        let dt: Float = 0.016
        let maxPerFrame: Float = (Float.pi / 90) * dt
        // Exhaust acquiring mode with north camera (offset stays near 0).
        for _ in 0..<5 {
            cal.step(cameraTransform: northFacingCamera, trueHeadingDeg: 0,
                     headingAccuracy: 5, dt: dt)
        }
        // Tracking mode: one step with a large correction must not exceed the slew cap.
        cal.step(cameraTransform: eastFacingCamera, trueHeadingDeg: 0,
                 headingAccuracy: 5, dt: dt)
        #expect(abs(cal.currentOffset) <= maxPerFrame + 1e-5)
    }

    @Test func slewContinuesWhenCompassGated() {
        let cal = NorthCalibrator()
        let dt: Float = 0.016
        // Exhaust acquiring mode first (north camera, same heading → correction ≈ 0).
        for _ in 0..<5 {
            cal.step(cameraTransform: northFacingCamera, trueHeadingDeg: 0,
                     headingAccuracy: 5, dt: dt)
        }
        // Seed a non-zero target in tracking mode using the east camera.
        for _ in 0..<5 {
            cal.step(cameraTransform: eastFacingCamera, trueHeadingDeg: 0,
                     headingAccuracy: 5, dt: dt)
        }
        let offsetAfterSeed = cal.currentOffset
        // Now feed invalid headings — slew should still continue toward the negative target.
        for _ in 0..<20 {
            cal.step(cameraTransform: eastFacingCamera, trueHeadingDeg: -1,
                     headingAccuracy: 5, dt: dt)
        }
        #expect(cal.currentOffset < offsetAfterSeed)   // offset moved toward −π/2 target
    }
}
