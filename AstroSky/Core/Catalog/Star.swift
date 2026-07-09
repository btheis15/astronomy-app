//
//  Star.swift
//  AstroSky
//

import Foundation

struct Star: CelestialObject, Identifiable, Sendable {
    /// Catalog key, e.g. "sirius" or "alpUMi".
    let key: String
    /// Proper name if the star has one ("Sirius"), else the designation.
    let properName: String?
    /// Bayer designation, e.g. "α CMa".
    let bayer: String?
    /// Three-letter IAU constellation abbreviation, e.g. "CMa".
    let constellationAbbreviation: String
    /// J2000 right ascension in hours.
    let raHours: Double
    /// J2000 declination in degrees.
    let decDegrees: Double
    /// Apparent visual magnitude.
    let visualMagnitude: Double
    /// Color index B−V (drives rendered star color).
    let colorIndex: Double
    /// Distance in light-years, if known.
    let distanceLy: Double?

    init(_ key: String, name: String?, bayer: String?, con: String,
         ra: Double, dec: Double, mag: Double, bv: Double, ly: Double? = nil) {
        self.key = key
        self.properName = name
        self.bayer = bayer
        self.constellationAbbreviation = con
        self.raHours = ra
        self.decDegrees = dec
        self.visualMagnitude = mag
        self.colorIndex = bv
        self.distanceLy = ly
    }

    // MARK: CelestialObject

    var id: String { "star.\(key)" }

    var name: String { properName ?? bayer ?? key }

    var subtitle: String {
        let constellation = ConstellationCatalog.fullName(forAbbreviation: constellationAbbreviation)
        if let bayer, properName != nil {
            return "\(bayer) · \(constellation)"
        }
        return constellation
    }

    var kind: CelestialObjectKind { .star }
    var magnitude: Double? { visualMagnitude }

    var equatorialJ2000: EquatorialCoordinates {
        EquatorialCoordinates(raHours: raHours, decDegrees: decDegrees)
    }

    func skyPosition(julianDate jd: Double, observer: Observer) -> SkyPosition {
        let eq = equatorialJ2000
        return SkyPosition(equatorialJ2000: eq,
                           horizontal: horizontalFromJ2000(eq, julianDate: jd, observer: observer),
                           distanceDescription: distanceLy.map { AstroFormat.lightYears($0) })
    }

    func infoRows(julianDate jd: Double, observer: Observer) -> [(label: String, value: String)] {
        var rows: [(String, String)] = [
            ("Magnitude", AstroFormat.magnitude(visualMagnitude)),
            ("Spectral color", spectralDescription),
            ("Right ascension", AstroFormat.rightAscension(equatorialJ2000)),
            ("Declination", AstroFormat.declination(equatorialJ2000)),
        ]
        if let bayer {
            rows.insert(("Designation", bayer), at: 0)
        }
        if let distanceLy {
            rows.append(("Distance", AstroFormat.lightYears(distanceLy)))
        }
        return rows
    }

    /// Rough spectral description derived from the B−V color index.
    var spectralDescription: String {
        switch colorIndex {
        case ..<(-0.02): "Blue (O/B type)"
        case ..<0.30: "White (A type)"
        case ..<0.58: "Yellow-white (F type)"
        case ..<0.81: "Yellow (G type)"
        case ..<1.40: "Orange (K type)"
        default: "Red-orange (M type)"
        }
    }
}
