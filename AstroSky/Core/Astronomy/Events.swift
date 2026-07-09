//
//  Events.swift
//  AstroSky
//
//  Sky-events engine: scans the coming weeks for close conjunctions, the exact
//  instants of new/full Moon, eclipse possibilities (from Sun–Moon node
//  geometry at syzygy), and annual meteor-shower peaks.
//  References: Meeus, "Astronomical Algorithms", 2nd ed., chs. 47–54.
//

import Foundation

enum AstroEventKind: String, Sendable {
    case conjunction, fullMoon, newMoon, lunarEclipse, solarEclipse, meteorShower

    var iconSystemName: String {
        switch self {
        case .conjunction: "circle.circle"
        case .fullMoon: "moon.fill"
        case .newMoon: "moon"
        case .lunarEclipse: "moon.haze.fill"
        case .solarEclipse: "sun.max.trianglebadge.exclamationmark"
        case .meteorShower: "sparkles"
        }
    }
}

struct AstroEvent: Identifiable, Sendable {
    let id: String
    let kind: AstroEventKind
    let date: Date
    let title: String
    let detail: String
}

/// Annual meteor shower (fixed peak date + radiant, from the IMO working list).
struct MeteorShower: Sendable, Identifiable {
    let name: String
    let peakMonth: Int
    let peakDay: Int
    /// Days either side of the peak the shower is worth showing.
    let activeWindowDays: Int
    let radiantRAHours: Double
    let radiantDecDegrees: Double
    let zhr: Int

    var id: String { name }
    var radiant: EquatorialCoordinates {
        EquatorialCoordinates(raHours: radiantRAHours, decDegrees: radiantDecDegrees)
    }
}

enum MeteorShowers {
    /// The major annual showers (IMO working list — peak dates are UT, radiants J2000).
    static let all: [MeteorShower] = [
        MeteorShower(name: "Quadrantids", peakMonth: 1, peakDay: 3, activeWindowDays: 2,
                     radiantRAHours: 15.33, radiantDecDegrees: 49.5, zhr: 120),
        MeteorShower(name: "Lyrids", peakMonth: 4, peakDay: 22, activeWindowDays: 3,
                     radiantRAHours: 18.13, radiantDecDegrees: 33.3, zhr: 18),
        MeteorShower(name: "Eta Aquariids", peakMonth: 5, peakDay: 6, activeWindowDays: 4,
                     radiantRAHours: 22.47, radiantDecDegrees: -1.0, zhr: 50),
        MeteorShower(name: "Perseids", peakMonth: 8, peakDay: 12, activeWindowDays: 4,
                     radiantRAHours: 3.13, radiantDecDegrees: 58.0, zhr: 100),
        MeteorShower(name: "Orionids", peakMonth: 10, peakDay: 21, activeWindowDays: 4,
                     radiantRAHours: 6.33, radiantDecDegrees: 15.5, zhr: 20),
        MeteorShower(name: "Leonids", peakMonth: 11, peakDay: 17, activeWindowDays: 3,
                     radiantRAHours: 10.13, radiantDecDegrees: 21.6, zhr: 15),
        MeteorShower(name: "Geminids", peakMonth: 12, peakDay: 14, activeWindowDays: 3,
                     radiantRAHours: 7.47, radiantDecDegrees: 32.2, zhr: 150),
    ]

    /// Showers active on `date` (within their window of this year's peak).
    static func active(on date: Date) -> [MeteorShower] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let year = calendar.component(.year, from: date)
        return all.filter { shower in
            for y in [year - 1, year] {
                var components = DateComponents()
                components.year = y; components.month = shower.peakMonth; components.day = shower.peakDay
                components.hour = 12
                guard let peak = calendar.date(from: components) else { continue }
                let window = Double(shower.activeWindowDays) * 86_400
                if abs(date.timeIntervalSince(peak)) <= window { return true }
            }
            return false
        }
    }
}

enum EventsEngine {
    /// Objects considered for conjunctions.
    private static let conjunctionThreshold = 2.0 * AstroMath.degToRad

    /// Scan `days` days from `start` for upcoming sky events, date-sorted.
    static func upcoming(observer: Observer, startingAt start: Date, days: Int = 30) -> [AstroEvent] {
        var events: [AstroEvent] = []
        events.append(contentsOf: moonPhaseEvents(startingAt: start, days: days))
        events.append(contentsOf: conjunctionEvents(startingAt: start, days: days))
        events.append(contentsOf: meteorEvents(startingAt: start, days: days))
        return events.sorted { $0.date < $1.date }
    }

    // MARK: Moon phases + eclipses

    /// Signed Sun→Moon elongation in ecliptic longitude, radians (−π, π].
    static func moonSunElongation(julianDate jd: Double) -> Double {
        let moon = MoonEphemeris.position(julianDate: jd).ecliptic.longitude
        let sun = SunEphemeris.position(julianDate: jd).ecliptic.longitude
        return AstroMath.signedRadians(moon - sun)
    }

    /// Find the instant a target elongation is reached, refining a bracket by
    /// bisection. `target` is 0 (new) or π (full).
    static func moonPhaseInstants(startingAt start: Date, days: Int,
                                  target: Double) -> [Date] {
        // Work with the phase angle measured from `target` so we look for its
        // zero crossing on a continuous, wrapped quantity.
        func offset(_ jd: Double) -> Double {
            AstroMath.signedRadians(moonSunElongation(julianDate: jd) - target)
        }
        var results: [Date] = []
        let startJD = AstroTime.julianDate(start)
        let step = 0.25   // days
        var t0 = startJD
        var f0 = offset(t0)
        let endJD = startJD + Double(days)
        while t0 < endJD {
            let t1 = t0 + step
            let f1 = offset(t1)
            // A sign change that is not the ±π wrap (guard against the 2π jump).
            if f0 <= 0 && f1 > 0 && abs(f1 - f0) < .pi {
                var lo = t0, hi = t1
                for _ in 0..<40 {
                    let mid = (lo + hi) / 2
                    if offset(mid) <= 0 { lo = mid } else { hi = mid }
                }
                results.append(AstroTime.date(julianDate: (lo + hi) / 2))
            }
            t0 = t1; f0 = f1
        }
        return results
    }

    private static func moonPhaseEvents(startingAt start: Date, days: Int) -> [AstroEvent] {
        var events: [AstroEvent] = []
        for date in moonPhaseInstants(startingAt: start, days: days, target: .pi) {
            let eclipse = eclipseSeverity(julianDate: AstroTime.julianDate(date))
            if eclipse.isLunar {
                events.append(AstroEvent(id: "lunecl-\(Int(date.timeIntervalSince1970))",
                                         kind: .lunarEclipse, date: date,
                                         title: "Lunar eclipse", detail: eclipse.description))
            } else {
                events.append(AstroEvent(id: "full-\(Int(date.timeIntervalSince1970))",
                                         kind: .fullMoon, date: date,
                                         title: "Full Moon", detail: "The Moon is fully illuminated."))
            }
        }
        for date in moonPhaseInstants(startingAt: start, days: days, target: 0) {
            let eclipse = eclipseSeverity(julianDate: AstroTime.julianDate(date))
            if eclipse.isSolar {
                events.append(AstroEvent(id: "solecl-\(Int(date.timeIntervalSince1970))",
                                         kind: .solarEclipse, date: date,
                                         title: "Solar eclipse", detail: eclipse.description))
            } else {
                events.append(AstroEvent(id: "new-\(Int(date.timeIntervalSince1970))",
                                         kind: .newMoon, date: date,
                                         title: "New Moon", detail: "The Moon is between Earth and the Sun."))
            }
        }
        return events
    }

    private struct EclipsePossibility {
        let isSolar: Bool
        let isLunar: Bool
        let description: String
    }

    /// Rough eclipse test from the Moon's ecliptic latitude at syzygy: an
    /// eclipse is possible only near a node (Meeus ch. 54 limits).
    private static func eclipseSeverity(julianDate jd: Double) -> EclipsePossibility {
        let beta = abs(MoonEphemeris.position(julianDate: jd).ecliptic.latitude) * AstroMath.radToDeg
        let elongation = moonSunElongation(julianDate: jd)
        let isNew = abs(elongation) < 0.3
        let isFull = abs(abs(elongation) - .pi) < 0.3
        // Solar eclipse possible if |β| < ~1.4° at new Moon; lunar if < ~1.0° at full.
        let solar = isNew && beta < 1.4
        let lunar = isFull && beta < 1.0
        let detail = "The Moon passes near a node — an eclipse is possible somewhere on Earth."
        return EclipsePossibility(isSolar: solar, isLunar: lunar, description: detail)
    }

    // MARK: Conjunctions

    private static func conjunctionEvents(startingAt start: Date, days: Int) -> [AstroEvent] {
        // Bodies to pair up: Moon + visible planets.
        struct Body { let name: String; let equatorial: (Double) -> EquatorialCoordinates }
        var bodies: [Body] = [
            Body(name: "Moon") { jd in
                CoordinateTransforms.precessFromJ2000(
                    // Moon equatorial is already of-date; treat as-is by round-tripping J2000.
                    MoonEphemeris.position(julianDate: jd).equatorial, julianDate: AstroTime.j2000)
            }
        ]
        for planet in Planet.visible {
            bodies.append(Body(name: planet.name) { jd in
                CoordinateTransforms.precessFromJ2000(
                    PlanetEphemeris.position(of: planet, julianDate: jd).equatorialJ2000, julianDate: jd)
            })
        }

        var events: [AstroEvent] = []
        let startJD = AstroTime.julianDate(start)
        for i in 0..<bodies.count {
            for j in (i + 1)..<bodies.count {
                if let event = closestApproach(bodies[i].name, bodies[i].equatorial,
                                               bodies[j].name, bodies[j].equatorial,
                                               startJD: startJD, days: days) {
                    events.append(event)
                }
            }
        }
        return events
    }

    private static func closestApproach(_ nameA: String, _ eqA: (Double) -> EquatorialCoordinates,
                                        _ nameB: String, _ eqB: (Double) -> EquatorialCoordinates,
                                        startJD: Double, days: Int) -> AstroEvent? {
        func sep(_ jd: Double) -> Double {
            CoordinateTransforms.angularSeparation(eqA(jd), eqB(jd))
        }
        // Coarse daily scan for the minimum, then golden-section refine.
        var bestJD = startJD
        var bestSep = Double.pi
        var t = startJD
        while t <= startJD + Double(days) {
            let s = sep(t)
            if s < bestSep { bestSep = s; bestJD = t }
            t += 1.0
        }
        guard bestSep < conjunctionThreshold * 3 else { return nil }   // only refine near approaches
        // Golden-section on [bestJD-1, bestJD+1].
        var lo = bestJD - 1, hi = bestJD + 1
        let phi = 0.6180339887
        var c = hi - phi * (hi - lo), d = lo + phi * (hi - lo)
        for _ in 0..<40 {
            if sep(c) < sep(d) { hi = d } else { lo = c }
            c = hi - phi * (hi - lo); d = lo + phi * (hi - lo)
        }
        let minJD = (lo + hi) / 2
        let minSep = sep(minJD)
        guard minSep < conjunctionThreshold else { return nil }
        let date = AstroTime.date(julianDate: minJD)
        let degrees = minSep * AstroMath.radToDeg
        return AstroEvent(id: "conj-\(nameA)-\(nameB)-\(Int(date.timeIntervalSince1970))",
                          kind: .conjunction, date: date,
                          title: "\(nameA) & \(nameB) conjunction",
                          detail: String(format: "Separation %.1f°.", degrees))
    }

    // MARK: Meteor showers

    private static func meteorEvents(startingAt start: Date, days: Int) -> [AstroEvent] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let end = start.addingTimeInterval(Double(days) * 86_400)
        var events: [AstroEvent] = []
        for shower in MeteorShowers.all {
            for year in [calendar.component(.year, from: start), calendar.component(.year, from: end)] {
                var components = DateComponents()
                components.year = year; components.month = shower.peakMonth; components.day = shower.peakDay
                components.hour = 6
                guard let peak = calendar.date(from: components),
                      peak >= start && peak <= end else { continue }
                events.append(AstroEvent(id: "meteor-\(shower.name)-\(year)",
                                         kind: .meteorShower, date: peak,
                                         title: "\(shower.name) peak",
                                         detail: "Up to ~\(shower.zhr) meteors/hour under dark skies."))
            }
        }
        return events
    }
}
