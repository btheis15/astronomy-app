//
//  RiseSet.swift
//  AstroSky
//
//  Rise / transit / set and twilight computation.
//
//  Instead of the classical interpolation method (which needs special-casing
//  for the fast-moving Moon and for objects that never cross the horizon),
//  we sample the altitude curve over the requested day and refine the
//  crossings by bisection. Robust for every object type this app handles.
//

import Foundation

struct RiseSetEvents {
    var rise: Date?
    var transit: Date?
    var set: Date?
    /// Altitude at transit, radians.
    var transitAltitude: Double?
    /// True if the object stays above the threshold all day.
    var alwaysUp: Bool
    /// True if the object stays below the threshold all day.
    var alwaysDown: Bool
}

struct TwilightTimes {
    var sunrise: Date?
    var sunset: Date?
    var civilDawn: Date?
    var civilDusk: Date?
    var nauticalDawn: Date?
    var nauticalDusk: Date?
    var astronomicalDawn: Date?
    var astronomicalDusk: Date?
    var solarNoon: Date?
}

enum RiseSetCalculator {
    /// Standard altitude thresholds (radians) at which an object is
    /// considered to rise or set.
    enum Threshold {
        /// Upper limb of the Sun with refraction: -0.833°.
        static let sun = -0.833 * AstroMath.degToRad
        /// Center of the Moon, refraction and parallax roughly cancelled: +0.125°.
        static let moon = 0.125 * AstroMath.degToRad
        /// Point source with refraction: -0.567°.
        static let star = -0.567 * AstroMath.degToRad
    }

    /// Compute rise/transit/set events between `start` and `start + 1 day`.
    /// - Parameters:
    ///   - altitudeAt: closure returning the true altitude (radians) of the
    ///     object at a given date, for the observer in question.
    ///   - threshold: altitude defining the rise/set horizon.
    static func events(startingAt start: Date,
                       threshold: Double = Threshold.star,
                       altitudeAt: (Date) -> Double) -> RiseSetEvents {
        let dayLength: TimeInterval = 86_400
        let stepCount = 288                       // 5-minute sampling
        let step = dayLength / Double(stepCount)

        var samples: [(date: Date, altitude: Double)] = []
        samples.reserveCapacity(stepCount + 1)
        for i in 0...stepCount {
            let date = start.addingTimeInterval(Double(i) * step)
            samples.append((date, altitudeAt(date)))
        }

        var rise: Date?
        var set: Date?
        var transit: Date?
        var transitAltitude: Double?

        // Horizon crossings, refined by bisection.
        for i in 0..<stepCount {
            let a0 = samples[i].altitude - threshold
            let a1 = samples[i + 1].altitude - threshold
            guard a0 == 0 || a0.sign != a1.sign else { continue }
            let crossing = bisect(lower: samples[i].date, upper: samples[i + 1].date,
                                  threshold: threshold, altitudeAt: altitudeAt)
            if a0 < a1 {
                if rise == nil { rise = crossing }
            } else {
                if set == nil { set = crossing }
            }
        }

        // Transit: the local maximum of the altitude curve.
        var bestIndex = 0
        for (i, sample) in samples.enumerated() where sample.altitude > samples[bestIndex].altitude {
            bestIndex = i
        }
        if bestIndex > 0 && bestIndex < stepCount {
            let refined = refineMaximum(around: samples[bestIndex].date, halfWindow: step, altitudeAt: altitudeAt)
            transit = refined
            transitAltitude = altitudeAt(refined)
        } else {
            transit = samples[bestIndex].date
            transitAltitude = samples[bestIndex].altitude
        }

        let aboveCount = samples.filter { $0.altitude > threshold }.count
        let alwaysUp = aboveCount == samples.count
        let alwaysDown = aboveCount == 0

        return RiseSetEvents(rise: rise,
                             transit: transit,
                             set: set,
                             transitAltitude: transitAltitude,
                             alwaysUp: alwaysUp,
                             alwaysDown: alwaysDown)
    }

    /// Convenience for objects with a (slowly varying) equatorial position.
    static func events(for equatorialAt: @escaping (Double) -> EquatorialCoordinates,
                       observer: Observer,
                       startingAt start: Date,
                       threshold: Double = Threshold.star) -> RiseSetEvents {
        events(startingAt: start, threshold: threshold) { date in
            let jd = AstroTime.julianDate(date)
            let eq = equatorialAt(jd)
            return CoordinateTransforms.horizontal(of: eq, julianDate: jd, observer: observer).altitude
        }
    }

    /// Sun events and twilight boundaries for the day starting at `start`.
    static func twilight(observer: Observer, startingAt start: Date) -> TwilightTimes {
        func sunAltitude(_ date: Date) -> Double {
            let jd = AstroTime.julianDate(date)
            let eq = SunEphemeris.position(julianDate: jd).equatorial
            return CoordinateTransforms.horizontal(of: eq, julianDate: jd, observer: observer).altitude
        }

        let sunEvents = events(startingAt: start, threshold: Threshold.sun, altitudeAt: sunAltitude)
        let civil = events(startingAt: start, threshold: -6.0 * AstroMath.degToRad, altitudeAt: sunAltitude)
        let nautical = events(startingAt: start, threshold: -12.0 * AstroMath.degToRad, altitudeAt: sunAltitude)
        let astro = events(startingAt: start, threshold: -18.0 * AstroMath.degToRad, altitudeAt: sunAltitude)

        return TwilightTimes(sunrise: sunEvents.rise,
                             sunset: sunEvents.set,
                             civilDawn: civil.rise,
                             civilDusk: civil.set,
                             nauticalDawn: nautical.rise,
                             nauticalDusk: nautical.set,
                             astronomicalDawn: astro.rise,
                             astronomicalDusk: astro.set,
                             solarNoon: sunEvents.transit)
    }

    // MARK: - Private

    private static func bisect(lower: Date, upper: Date,
                               threshold: Double,
                               altitudeAt: (Date) -> Double) -> Date {
        var lo = lower
        var hi = upper
        let loSign = (altitudeAt(lo) - threshold) >= 0
        for _ in 0..<20 {   // ~0.3 s precision on a 5-minute bracket
            let mid = lo.addingTimeInterval(hi.timeIntervalSince(lo) / 2)
            if ((altitudeAt(mid) - threshold) >= 0) == loSign {
                lo = mid
            } else {
                hi = mid
            }
        }
        return lo.addingTimeInterval(hi.timeIntervalSince(lo) / 2)
    }

    private static func refineMaximum(around center: Date,
                                      halfWindow: TimeInterval,
                                      altitudeAt: (Date) -> Double) -> Date {
        // Golden-section search on the altitude curve.
        let phi = (sqrt(5.0) - 1) / 2
        var a = center.addingTimeInterval(-halfWindow)
        var b = center.addingTimeInterval(halfWindow)
        for _ in 0..<25 {
            let span = b.timeIntervalSince(a)
            let c = a.addingTimeInterval((1 - phi) * span)
            let d = a.addingTimeInterval(phi * span)
            if altitudeAt(c) < altitudeAt(d) {
                a = c
            } else {
                b = d
            }
        }
        return a.addingTimeInterval(b.timeIntervalSince(a) / 2)
    }
}
