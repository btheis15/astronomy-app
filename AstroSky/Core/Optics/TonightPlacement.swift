//
//  TonightPlacement.swift
//  AstroSky
//
//  How well-placed an object is during tonight's dark hours at the observer's
//  location — the basis for "best around <time>" and the Observe-tonight list.
//

import Foundation

struct TonightPlacement: Sendable {
    let maxAltitudeRadians: Double
    let bestTime: Date?
    var maxAltitudeDegrees: Double { maxAltitudeRadians * AstroMath.radToDeg }
    /// Rises to a useful altitude during the dark window.
    var isWellPlaced: Bool { maxAltitudeDegrees >= 20 }
}

enum TonightPlacementCalculator {
    /// Sample the object's altitude across tonight's astronomical-dark window
    /// and report the peak and when it occurs.
    static func compute(object: any CelestialObject, observer: Observer, date: Date) -> TonightPlacement {
        let dayStart = Calendar.current.startOfDay(for: date)
        let twilight = RiseSetCalculator.twilight(observer: observer, startingAt: dayStart)

        // Dark window: astronomical dusk → next astronomical dawn, else a
        // generous evening fallback (18:00 → 06:00) if the Sun never sets far.
        let start = twilight.astronomicalDusk ?? date.addingTimeInterval(0)
        let end = twilight.astronomicalDawn ?? start.addingTimeInterval(12 * 3600)
        let windowEnd = end > start ? end : start.addingTimeInterval(10 * 3600)

        var bestAlt = -Double.pi / 2
        var bestTime: Date?
        let total = windowEnd.timeIntervalSince(start)
        let steps = 48
        for i in 0...steps {
            let t = start.addingTimeInterval(total * Double(i) / Double(steps))
            let alt = object.horizontal(julianDate: AstroTime.julianDate(t), observer: observer).altitude
            if alt > bestAlt { bestAlt = alt; bestTime = t }
        }
        return TonightPlacement(maxAltitudeRadians: bestAlt,
                                bestTime: bestAlt > 0 ? bestTime : nil)
    }
}
