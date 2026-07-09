//
//  TLE.swift
//  AstroSky
//
//  Two-Line Element set parsing (NORAD/Celestrak format).
//

import Foundation

struct TLE: Sendable, Codable, Equatable {
    var name: String
    var catalogNumber: Int
    /// Epoch as a Julian Date (UTC).
    var epochJD: Double
    /// Inclination, radians.
    var inclination: Double
    /// Right ascension of the ascending node, radians.
    var raan: Double
    /// Eccentricity (dimensionless).
    var eccentricity: Double
    /// Argument of perigee, radians.
    var argumentOfPerigee: Double
    /// Mean anomaly, radians.
    var meanAnomaly: Double
    /// Mean motion, revolutions per day.
    var meanMotionRevPerDay: Double
    /// B* drag term (1/earth radii).
    var bstar: Double

    /// Mean motion in radians per minute.
    var meanMotionRadPerMin: Double {
        meanMotionRevPerDay * AstroMath.twoPi / 1440.0
    }

    /// Orbital period in minutes.
    var periodMinutes: Double { 1440.0 / meanMotionRevPerDay }

    /// SGP4 (near-earth) handles orbits with periods under 225 minutes;
    /// everything this app tracks (ISS, Starlink, bright LEO satellites)
    /// qualifies. Deep-space objects are skipped.
    var isNearEarth: Bool { periodMinutes < 225.0 }
}

enum TLEError: Error, LocalizedError {
    case malformedLine(String)
    case badChecksum(line: Int)

    var errorDescription: String? {
        switch self {
        case .malformedLine(let details): "Malformed TLE line: \(details)"
        case .badChecksum(let line): "TLE checksum failed on line \(line)"
        }
    }
}

enum TLEParser {
    /// Parse a Celestrak-style text blob: repeating groups of
    /// [name line,] line 1, line 2.
    static func parse(text: String) -> [TLE] {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var result: [TLE] = []
        var pendingName: String?
        var pendingLine1: String?

        for line in lines {
            if line.hasPrefix("1 "), line.count >= 62 {
                pendingLine1 = line
            } else if line.hasPrefix("2 "), line.count >= 62, let line1 = pendingLine1 {
                if let tle = try? parse(name: pendingName ?? "Unknown", line1: line1, line2: line) {
                    result.append(tle)
                }
                pendingName = nil
                pendingLine1 = nil
            } else {
                pendingName = line
                pendingLine1 = nil
            }
        }
        return result
    }

    /// Parse one element set. Checksums are validated when the checksum
    /// column is a digit; some hand-edited TLEs omit it, so absence is not
    /// an error.
    static func parse(name: String, line1: String, line2: String) throws -> TLE {
        let l1 = Array(line1)
        let l2 = Array(line2)
        guard l1.count >= 63, l2.count >= 63 else {
            throw TLEError.malformedLine("line shorter than 63 characters")
        }

        func field(_ chars: [Character], _ range: ClosedRange<Int>) -> String {
            // Columns are 1-based in TLE documentation.
            String(chars[(range.lowerBound - 1)...(range.upperBound - 1)])
                .trimmingCharacters(in: .whitespaces)
        }

        if let checksum = l1.last?.wholeNumberValue, computedChecksum(line1) != checksum {
            throw TLEError.badChecksum(line: 1)
        }
        if let checksum = l2.last?.wholeNumberValue, computedChecksum(line2) != checksum {
            throw TLEError.badChecksum(line: 2)
        }

        guard let catalogNumber = Int(field(l1, 3...7)) else {
            throw TLEError.malformedLine("catalog number")
        }

        // Epoch: 2-digit year + fractional day of year.
        guard let epochYear2 = Int(field(l1, 19...20)),
              let epochDay = Double(field(l1, 21...32)) else {
            throw TLEError.malformedLine("epoch")
        }
        let year = epochYear2 < 57 ? 2000 + epochYear2 : 1900 + epochYear2
        let epochJD = julianDate(year: year) + epochDay - 1.0

        let bstar = parseAssumedDecimalExponent(field(l1, 54...61))

        guard let inclination = Double(field(l2, 9...16)),
              let raan = Double(field(l2, 18...25)),
              let argp = Double(field(l2, 35...42)),
              let meanAnomaly = Double(field(l2, 44...51)),
              let meanMotion = Double(field(l2, 53...63)) else {
            throw TLEError.malformedLine("orbital elements")
        }
        let eccString = field(l2, 27...33)
        guard let eccDigits = Double(eccString) else {
            throw TLEError.malformedLine("eccentricity")
        }
        let eccentricity = eccDigits / 1e7

        return TLE(name: name,
                   catalogNumber: catalogNumber,
                   epochJD: epochJD,
                   inclination: inclination * AstroMath.degToRad,
                   raan: raan * AstroMath.degToRad,
                   eccentricity: eccentricity,
                   argumentOfPerigee: argp * AstroMath.degToRad,
                   meanAnomaly: meanAnomaly * AstroMath.degToRad,
                   meanMotionRevPerDay: meanMotion,
                   bstar: bstar)
    }

    /// Fields such as B* use an assumed decimal point and explicit exponent:
    /// " 36258-4" means 0.36258e-4.
    static func parseAssumedDecimalExponent(_ raw: String) -> Double {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return 0 }

        var mantissaSign = 1.0
        var body = Substring(s)
        if body.hasPrefix("-") { mantissaSign = -1; body = body.dropFirst() }
        else if body.hasPrefix("+") { body = body.dropFirst() }

        // Split at the exponent sign (last '+' or '-').
        guard let expSignIndex = body.lastIndex(where: { $0 == "+" || $0 == "-" }) else {
            return (Double(body) ?? 0) * mantissaSign
        }
        let digits = body[..<expSignIndex]
        let expPart = body[expSignIndex...]
        guard let mantissaDigits = Double(digits), let exponent = Int(expPart) else { return 0 }
        let mantissa = mantissaDigits / pow(10.0, Double(digits.count))
        return mantissaSign * mantissa * pow(10.0, Double(exponent))
    }

    /// Modulo-10 checksum: digits count as value, '-' counts as 1.
    static func computedChecksum(_ line: String) -> Int {
        var sum = 0
        for ch in line.dropLast() {
            if let v = ch.wholeNumberValue { sum += v }
            else if ch == "-" { sum += 1 }
        }
        return sum % 10
    }

    /// Julian date of Jan 1.0 of a Gregorian year.
    private static func julianDate(year: Int) -> Double {
        var components = DateComponents()
        components.year = year
        components.month = 1
        components.day = 1
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: components)!
        return AstroTime.julianDate(date)
    }
}
