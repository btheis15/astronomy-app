//
//  Formatting.swift
//  AstroSky
//
//  Human-readable formatting of astronomical quantities.
//

import Foundation

enum AstroFormat {
    /// "5h 16m 41s" style right ascension.
    static func rightAscension(_ eq: EquatorialCoordinates) -> String {
        var hours = eq.raHours.truncatingRemainder(dividingBy: 24)
        if hours < 0 { hours += 24 }
        let h = Int(hours)
        let minutes = (hours - Double(h)) * 60
        let m = Int(minutes)
        let s = Int(((minutes - Double(m)) * 60).rounded())
        return String(format: "%dh %02dm %02ds", h, m, min(s, 59))
    }

    /// "+45° 59′" style declination.
    static func declination(_ eq: EquatorialCoordinates) -> String {
        let deg = eq.decDegrees
        let sign = deg < 0 ? "−" : "+"
        let absDeg = abs(deg)
        let d = Int(absDeg)
        let m = Int(((absDeg - Double(d)) * 60).rounded())
        return String(format: "%@%d° %02d′", sign, d, min(m, 59))
    }

    /// "+34.2°" style signed degrees.
    static func degrees(_ radians: Double, decimals: Int = 1) -> String {
        String(format: "%+.\(decimals)f°", radians * AstroMath.radToDeg)
    }

    /// "212° SW" style azimuth.
    static func azimuth(_ horizontal: HorizontalCoordinates) -> String {
        String(format: "%.0f° %@", horizontal.azimuthDegrees, horizontal.compassDirection)
    }

    /// Magnitude, e.g. "−1.46" or "4.5".
    static func magnitude(_ value: Double) -> String {
        let s = String(format: "%.1f", value)
        return s.replacingOccurrences(of: "-", with: "−")
    }

    /// Distance for display, choosing sensible units.
    static func distanceAU(_ au: Double) -> String {
        if au < 0.01 {
            return String(format: "%.0f km", au * AstroMath.auKilometers)
        }
        return String(format: "%.3f AU", au)
    }

    static func distanceKm(_ km: Double) -> String {
        if km > 1_000_000 {
            return String(format: "%.2f million km", km / 1_000_000)
        }
        return String(format: "%.0f km", km)
    }

    static func lightYears(_ ly: Double) -> String {
        ly >= 100 ? String(format: "%.0f ly", ly) : String(format: "%.1f ly", ly)
    }

    /// Angular size like "31.5′" or "42″".
    static func angularSize(_ radians: Double) -> String {
        let arcmin = radians * AstroMath.radToDeg * 60
        if arcmin >= 1 {
            return String(format: "%.1f′", arcmin)
        }
        return String(format: "%.0f″", arcmin * 60)
    }

    static func time(_ date: Date?, timeZone: TimeZone = .current) -> String {
        guard let date else { return "—" }
        // DateFormatter is expensive to allocate — reuse one static instance.
        timeFormatter.timeZone = timeZone
        return timeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()
}
