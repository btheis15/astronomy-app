//
//  NorthCalibrator.swift
//  AstroSky
//
//  Fuses CLHeading (absolute north) with the ARKit camera transform to
//  produce a smooth, deadbanded Y-rotation offset applied atop the sidereal
//  sky orientation every frame. Used only when ARWorldTracking runs with
//  `.gravity` alignment (no built-in compass lock).
//
//  Math:
//    ARKit world azimuth of the camera forward  = atan2(fwdX, -fwdZ)
//      where fwd = -cameraTransform.columns.2
//      (azimuth 0 ≡ world -Z direction)
//
//    Geographic azimuth of the ARKit world -Z  = trueHeadingDeg - arkitAz
//
//    Required correction so scene "North" (−Z) aligns with geographic North:
//      northOffset = arkitAz − trueHeadingRad
//
//  The correction is filtered through a circular low-pass (sin/cos space
//  to avoid 0/360 wraparound) and slewed frame-by-frame to avoid jumps.
//

import ARKit
import simd

@MainActor
final class NorthCalibrator {

    // MARK: Tuning

    /// Low-pass filter gain per frame (≈0.05 at 60 Hz ⟹ τ ≈ 0.3 s).
    private let filterK: Double = 0.05
    /// Skip a new measurement if it differs from the current target by less
    /// than this — prevents noisy flutter when the heading is stable.
    private let deadbandRad: Double = .pi / 180   // 1°
    /// Maximum rate at which currentOffset slews toward targetOffset.
    private let maxSlewPerSecond: Float = .pi / 90 // 2°/s
    /// Reject compass readings coarser than this.
    private let maxAccuracyDeg: Double = 30

    // MARK: State

    /// The Y-rotation (radians) actually applied to the sky root each frame.
    /// Slews toward `targetOffset` at `maxSlewPerSecond`.
    private(set) var currentOffset: Float = 0

    private var targetOffset: Float = 0

    // Circular low-pass accumulator (avoids 0/360 wraparound).
    private var sinAcc: Double = 0
    private var cosAcc: Double = 1

    // MARK: Update

    /// Called every rendered frame from SceneEvents.Update.
    ///
    /// - Parameters:
    ///   - cameraTransform: `ARFrame.camera.transform` (column-major 4×4).
    ///   - trueHeadingDeg: `CLHeading.trueHeading` (0 = North, 90 = East).
    ///     Negative values indicate an invalid reading — skips measurement.
    ///   - headingAccuracy: `CLHeading.headingAccuracy` in degrees, or nil.
    ///   - dt: Time since last frame in seconds.
    func step(cameraTransform: simd_float4x4,
              trueHeadingDeg: Double,
              headingAccuracy: Double?,
              dt: Float) {
        // Always slew toward the target, even when the compass reading is skipped.
        let diff = angleDiff(targetOffset, currentOffset)
        let maxStep = maxSlewPerSecond * dt
        currentOffset += min(max(diff, -maxStep), maxStep)

        // Gate: skip when compass is unavailable or inaccurate.
        guard trueHeadingDeg >= 0,
              let accuracy = headingAccuracy,
              accuracy <= maxAccuracyDeg else { return }

        // ARKit camera forward in world space = −(column 2 of camera transform).
        let col2 = cameraTransform.columns.2
        let fwdX = -col2.x
        let fwdZ = -col2.z
        // Azimuth in ARKit world frame: 0 = world −Z, π/2 = world +X.
        let arkitAzRad = Double(atan2(fwdX, -fwdZ))

        // Correction = arkitAz − trueHeadingRad  (see file header for derivation).
        var rawDelta = arkitAzRad - trueHeadingDeg * (.pi / 180)
        // Normalise to (−π, π].
        while rawDelta >  .pi { rawDelta -= 2 * .pi }
        while rawDelta <= -.pi { rawDelta += 2 * .pi }

        // Deadband: skip if the new measurement is too close to the current target.
        var deltaToTarget = rawDelta - Double(targetOffset)
        while deltaToTarget >  .pi { deltaToTarget -= 2 * .pi }
        while deltaToTarget <= -.pi { deltaToTarget += 2 * .pi }
        guard abs(deltaToTarget) > deadbandRad else { return }

        // Circular low-pass to avoid 0/360 wraparound artifacts.
        sinAcc = (1 - filterK) * sinAcc + filterK * sin(rawDelta)
        cosAcc = (1 - filterK) * cosAcc + filterK * cos(rawDelta)
        targetOffset = Float(atan2(sinAcc, cosAcc))
    }

    // MARK: Helpers

    /// Signed shortest-path angle from `current` to `target`, in (−π, π].
    private func angleDiff(_ target: Float, _ current: Float) -> Float {
        var d = target - current
        while d >  .pi { d -= 2 * .pi }
        while d <= -.pi { d += 2 * .pi }
        return d
    }
}
