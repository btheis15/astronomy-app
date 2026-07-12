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
//      northOffset = trueHeadingRad − arkitAz
//
//  The correction is filtered through a circular low-pass (sin/cos space
//  to avoid 0/360 wraparound) and slewed frame-by-frame to avoid jumps.
//
//  On cold start and after session resets, an acquiring regime is active:
//  the first `acquisitionSamples` quality-gated samples bypass the slew cap
//  and deadband and snap the sky to the correct heading immediately.
//

import ARKit
import simd

@MainActor
final class NorthCalibrator {

    // MARK: Tuning

    /// Low-pass filter gain in the slow-tracking regime (≈0.05 at 60 Hz ⟹ τ ≈ 0.3 s).
    private let filterK: Double = 0.05
    /// High-gain filter used during fast acquisition to converge in a few samples.
    private let acquisitionFilterK: Double = 0.5
    /// Quality-gated samples required before switching from acquiring to slow-tracking.
    private static let acquisitionSamples = 5
    /// Skip a new measurement if it differs from the current target by less
    /// than this — prevents noisy flutter when the heading is stable.
    private let deadbandRad: Double = .pi / 180   // 1°
    /// Maximum rate at which currentOffset slews toward targetOffset.
    private let maxSlewPerSecond: Float = .pi / 90 // 2°/s
    /// Reject compass readings coarser than this.
    private let maxAccuracyDeg: Double = 30
    /// Skip samples when the camera pitch exceeds this (pointing near-zenith).
    /// sin(65°) ≈ 0.906 — precomputed to avoid trig on every frame.
    private let zenithGateSinPitch: Double = 0.906  // sin(65°)

    // MARK: State

    /// Samples still needed before exiting the fast-acquisition regime.
    private var samplesRemaining = NorthCalibrator.acquisitionSamples

    private var isAcquiring: Bool { samplesRemaining > 0 }

    /// The Y-rotation (radians) actually applied to the sky root each frame.
    /// During acquisition, snaps directly to the circular mean.
    /// During tracking, slews toward `targetOffset` at `maxSlewPerSecond`.
    private(set) var currentOffset: Float = 0

    private var targetOffset: Float = 0

    // Circular low-pass accumulator (avoids 0/360 wraparound).
    private var sinAcc: Double = 0
    private var cosAcc: Double = 1

    // MARK: Reset

    /// Zeroes currentOffset and targetOffset without touching the circular
    /// accumulator or re-entering acquiring mode. Used when the caller folds
    /// the current offset into an external value and wants the calibrator to
    /// continue tracking from zero.
    func foldAndZero() {
        currentOffset = 0
        targetOffset = 0
    }

    /// Clears all accumulators and re-enters the fast-acquisition regime.
    /// Call whenever the AR session restarts or is interrupted.
    func reset() {
        samplesRemaining = NorthCalibrator.acquisitionSamples
        targetOffset = 0
        currentOffset = 0
        sinAcc = 0
        cosAcc = 1
    }

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
        // Tracking regime: slew currentOffset toward targetOffset.
        if !isAcquiring {
            let diff = angleDiff(targetOffset, currentOffset)
            let maxStep = maxSlewPerSecond * dt
            currentOffset += min(max(diff, -maxStep), maxStep)
        }

        // Gate: skip when compass is unavailable or inaccurate.
        guard trueHeadingDeg >= 0,
              let accuracy = headingAccuracy,
              accuracy <= maxAccuracyDeg else { return }

        // ARKit camera forward in world space = −(column 2 of camera transform).
        let col2 = cameraTransform.columns.2
        let fwdX = -col2.x
        let fwdZ = -col2.z

        // Pitch gate: skip when camera points within 25° of zenith.
        // fwdY ≈ sin(cameraPitch) for a unit forward vector (+Y = up in ARKit gravity mode).
        let fwdY = Double(-col2.y)
        guard abs(fwdY) < zenithGateSinPitch else { return }

        // Azimuth in ARKit world frame: 0 = world −Z, π/2 = world +X.
        let arkitAzRad = Double(atan2(fwdX, -fwdZ))

        // Correction = trueHeadingRad − arkitAz  (see file header for derivation).
        var rawDelta = trueHeadingDeg * (.pi / 180) - arkitAzRad
        // Normalise to (−π, π].
        while rawDelta >  .pi { rawDelta -= 2 * .pi }
        while rawDelta <= -.pi { rawDelta += 2 * .pi }

        if isAcquiring {
            // Fast path: bypass deadband; use high-gain filter and snap currentOffset.
            sinAcc = (1 - acquisitionFilterK) * sinAcc + acquisitionFilterK * sin(rawDelta)
            cosAcc = (1 - acquisitionFilterK) * cosAcc + acquisitionFilterK * cos(rawDelta)
            targetOffset = Float(atan2(sinAcc, cosAcc))
            currentOffset = targetOffset
            samplesRemaining -= 1
            return
        }

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
