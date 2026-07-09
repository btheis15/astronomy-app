//
//  MessierCatalog.swift
//  AstroSky
//
//  The complete Messier catalog (M1–M110). Positions are J2000
//  (RA in hours, Dec in degrees); magnitudes are integrated visual
//  magnitudes. Coordinates are catalog values rounded to display precision.
//

import Foundation

enum DeepSkyType: String, Sendable, CaseIterable {
    case galaxy = "Galaxy"
    case globularCluster = "Globular Cluster"
    case openCluster = "Open Cluster"
    case nebula = "Nebula"
    case planetaryNebula = "Planetary Nebula"
    case supernovaRemnant = "Supernova Remnant"
    case starCloud = "Star Cloud"
    case asterism = "Asterism"
}

/// Which deep-sky catalog an object comes from.
enum DeepSkyCatalog: Sendable {
    case messier, caldwell, ngc
}

struct DeepSkyObject: CelestialObject, Identifiable, Sendable {
    let catalog: DeepSkyCatalog
    /// Number within its catalog (Messier 1–110, Caldwell 1–109, or NGC number).
    let catalogNumber: Int
    let commonName: String?
    let type: DeepSkyType
    let constellationAbbreviation: String
    let raHours: Double
    let decDegrees: Double
    let visualMagnitude: Double

    /// Messier initializer (positional, matches the existing catalog rows).
    init(_ number: Int, _ name: String?, _ type: DeepSkyType, _ con: String,
         _ ra: Double, _ dec: Double, _ mag: Double) {
        self.catalog = .messier
        self.catalogNumber = number
        self.commonName = name
        self.type = type
        self.constellationAbbreviation = con
        self.raHours = ra
        self.decDegrees = dec
        self.visualMagnitude = mag
    }

    /// General initializer for any catalog.
    init(catalog: DeepSkyCatalog, number: Int, name: String?, type: DeepSkyType,
         constellation con: String, raHours ra: Double, decDegrees dec: Double, magnitude mag: Double) {
        self.catalog = catalog
        self.catalogNumber = number
        self.commonName = name
        self.type = type
        self.constellationAbbreviation = con
        self.raHours = ra
        self.decDegrees = dec
        self.visualMagnitude = mag
    }

    /// Back-compatible Messier number accessor (used by tests / Messier code).
    var messierNumber: Int { catalogNumber }

    // MARK: CelestialObject

    var id: String {
        switch catalog {
        case .messier: return String(format: "m%03d", catalogNumber)
        case .caldwell: return String(format: "c%03d", catalogNumber)
        case .ngc: return "ngc\(catalogNumber)"
        }
    }

    var designation: String {
        switch catalog {
        case .messier: return "M\(catalogNumber)"
        case .caldwell: return "C\(catalogNumber)"
        case .ngc: return "NGC \(catalogNumber)"
        }
    }

    var name: String { commonName.map { "\(designation) · \($0)" } ?? designation }

    var subtitle: String {
        "\(type.rawValue) · \(ConstellationCatalog.fullName(forAbbreviation: constellationAbbreviation))"
    }

    var kind: CelestialObjectKind { .deepSky }
    var magnitude: Double? { visualMagnitude }

    var equatorialJ2000: EquatorialCoordinates {
        EquatorialCoordinates(raHours: raHours, decDegrees: decDegrees)
    }

    func skyPosition(julianDate jd: Double, observer: Observer) -> SkyPosition {
        let eq = equatorialJ2000
        return SkyPosition(equatorialJ2000: eq,
                           horizontal: horizontalFromJ2000(eq, julianDate: jd, observer: observer),
                           distanceDescription: nil)
    }

    func infoRows(julianDate jd: Double, observer: Observer) -> [(label: String, value: String)] {
        [
            ("Type", type.rawValue),
            ("Magnitude", AstroFormat.magnitude(visualMagnitude)),
            ("Right ascension", AstroFormat.rightAscension(equatorialJ2000)),
            ("Declination", AstroFormat.declination(equatorialJ2000)),
            ("Constellation", ConstellationCatalog.fullName(forAbbreviation: constellationAbbreviation)),
        ]
    }
}

enum MessierCatalog {
    static let objects: [DeepSkyObject] = [
        DeepSkyObject(1, "Crab Nebula", .supernovaRemnant, "Tau", 5.575, 22.017, 8.4),
        DeepSkyObject(2, nil, .globularCluster, "Aqr", 21.558, -0.823, 6.5),
        DeepSkyObject(3, nil, .globularCluster, "CVn", 13.703, 28.377, 6.2),
        DeepSkyObject(4, nil, .globularCluster, "Sco", 16.393, -26.526, 5.9),
        DeepSkyObject(5, nil, .globularCluster, "Ser", 15.310, 2.083, 5.6),
        DeepSkyObject(6, "Butterfly Cluster", .openCluster, "Sco", 17.668, -32.217, 4.2),
        DeepSkyObject(7, "Ptolemy Cluster", .openCluster, "Sco", 17.898, -34.793, 3.3),
        DeepSkyObject(8, "Lagoon Nebula", .nebula, "Sgr", 18.060, -24.387, 6.0),
        DeepSkyObject(9, nil, .globularCluster, "Oph", 17.320, -18.516, 8.4),
        DeepSkyObject(10, nil, .globularCluster, "Oph", 16.953, -4.100, 6.4),
        DeepSkyObject(11, "Wild Duck Cluster", .openCluster, "Sct", 18.851, -6.271, 6.3),
        DeepSkyObject(12, nil, .globularCluster, "Oph", 16.787, -1.949, 7.7),
        DeepSkyObject(13, "Great Hercules Cluster", .globularCluster, "Her", 16.695, 36.460, 5.8),
        DeepSkyObject(14, nil, .globularCluster, "Oph", 17.626, -3.246, 8.3),
        DeepSkyObject(15, "Great Pegasus Cluster", .globularCluster, "Peg", 21.500, 12.167, 6.2),
        DeepSkyObject(16, "Eagle Nebula", .nebula, "Ser", 18.313, -13.783, 6.4),
        DeepSkyObject(17, "Omega Nebula", .nebula, "Sgr", 18.346, -16.172, 6.0),
        DeepSkyObject(18, nil, .openCluster, "Sgr", 18.333, -17.100, 7.5),
        DeepSkyObject(19, nil, .globularCluster, "Oph", 17.043, -26.268, 7.5),
        DeepSkyObject(20, "Trifid Nebula", .nebula, "Sgr", 18.045, -23.030, 6.3),
        DeepSkyObject(21, nil, .openCluster, "Sgr", 18.076, -22.500, 6.5),
        DeepSkyObject(22, "Sagittarius Cluster", .globularCluster, "Sgr", 18.607, -23.904, 5.1),
        DeepSkyObject(23, nil, .openCluster, "Sgr", 17.949, -18.986, 6.9),
        DeepSkyObject(24, "Sagittarius Star Cloud", .starCloud, "Sgr", 18.280, -18.550, 4.6),
        DeepSkyObject(25, nil, .openCluster, "Sgr", 18.529, -19.250, 4.6),
        DeepSkyObject(26, nil, .openCluster, "Sct", 18.755, -9.400, 8.0),
        DeepSkyObject(27, "Dumbbell Nebula", .planetaryNebula, "Vul", 19.994, 22.721, 7.4),
        DeepSkyObject(28, nil, .globularCluster, "Sgr", 18.409, -24.870, 6.8),
        DeepSkyObject(29, nil, .openCluster, "Cyg", 20.399, 38.523, 7.1),
        DeepSkyObject(30, nil, .globularCluster, "Cap", 21.673, -23.180, 7.2),
        DeepSkyObject(31, "Andromeda Galaxy", .galaxy, "And", 0.712, 41.269, 3.4),
        DeepSkyObject(32, nil, .galaxy, "And", 0.712, 40.865, 8.1),
        DeepSkyObject(33, "Triangulum Galaxy", .galaxy, "Tri", 1.564, 30.660, 5.7),
        DeepSkyObject(34, nil, .openCluster, "Per", 2.702, 42.783, 5.5),
        DeepSkyObject(35, nil, .openCluster, "Gem", 6.148, 24.333, 5.1),
        DeepSkyObject(36, nil, .openCluster, "Aur", 5.605, 34.135, 6.0),
        DeepSkyObject(37, nil, .openCluster, "Aur", 5.873, 32.550, 5.6),
        DeepSkyObject(38, nil, .openCluster, "Aur", 5.478, 35.855, 6.4),
        DeepSkyObject(39, nil, .openCluster, "Cyg", 21.530, 48.433, 4.6),
        DeepSkyObject(40, "Winnecke 4", .asterism, "UMa", 12.370, 58.083, 8.4),
        DeepSkyObject(41, nil, .openCluster, "CMa", 6.767, -20.733, 4.5),
        DeepSkyObject(42, "Orion Nebula", .nebula, "Ori", 5.588, -5.391, 4.0),
        DeepSkyObject(43, "De Mairan's Nebula", .nebula, "Ori", 5.593, -5.267, 9.0),
        DeepSkyObject(44, "Beehive Cluster", .openCluster, "Cnc", 8.670, 19.983, 3.1),
        DeepSkyObject(45, "Pleiades", .openCluster, "Tau", 3.790, 24.117, 1.6),
        DeepSkyObject(46, nil, .openCluster, "Pup", 7.696, -14.810, 6.1),
        DeepSkyObject(47, nil, .openCluster, "Pup", 7.610, -14.500, 4.4),
        DeepSkyObject(48, nil, .openCluster, "Hya", 8.229, -5.800, 5.8),
        DeepSkyObject(49, nil, .galaxy, "Vir", 12.497, 8.000, 8.4),
        DeepSkyObject(50, nil, .openCluster, "Mon", 7.053, -8.337, 5.9),
        DeepSkyObject(51, "Whirlpool Galaxy", .galaxy, "CVn", 13.498, 47.195, 8.4),
        DeepSkyObject(52, nil, .openCluster, "Cas", 23.413, 61.593, 6.9),
        DeepSkyObject(53, nil, .globularCluster, "Com", 13.215, 18.169, 7.6),
        DeepSkyObject(54, nil, .globularCluster, "Sgr", 18.917, -30.478, 7.6),
        DeepSkyObject(55, nil, .globularCluster, "Sgr", 19.667, -30.964, 6.3),
        DeepSkyObject(56, nil, .globularCluster, "Lyr", 19.276, 30.183, 8.3),
        DeepSkyObject(57, "Ring Nebula", .planetaryNebula, "Lyr", 18.893, 33.029, 8.8),
        DeepSkyObject(58, nil, .galaxy, "Vir", 12.629, 11.818, 9.7),
        DeepSkyObject(59, nil, .galaxy, "Vir", 12.700, 11.647, 9.6),
        DeepSkyObject(60, nil, .galaxy, "Vir", 12.728, 11.552, 8.8),
        DeepSkyObject(61, nil, .galaxy, "Vir", 12.365, 4.474, 9.7),
        DeepSkyObject(62, nil, .globularCluster, "Oph", 17.021, -30.114, 6.5),
        DeepSkyObject(63, "Sunflower Galaxy", .galaxy, "CVn", 13.264, 42.029, 8.6),
        DeepSkyObject(64, "Black Eye Galaxy", .galaxy, "Com", 12.945, 21.683, 8.5),
        DeepSkyObject(65, nil, .galaxy, "Leo", 11.315, 13.092, 9.3),
        DeepSkyObject(66, nil, .galaxy, "Leo", 11.337, 12.991, 8.9),
        DeepSkyObject(67, nil, .openCluster, "Cnc", 8.855, 11.800, 6.1),
        DeepSkyObject(68, nil, .globularCluster, "Hya", 12.658, -26.744, 7.8),
        DeepSkyObject(69, nil, .globularCluster, "Sgr", 18.523, -32.348, 7.6),
        DeepSkyObject(70, nil, .globularCluster, "Sgr", 18.720, -32.292, 7.9),
        DeepSkyObject(71, nil, .globularCluster, "Sge", 19.896, 18.779, 8.2),
        DeepSkyObject(72, nil, .globularCluster, "Aqr", 20.891, -12.537, 9.3),
        DeepSkyObject(73, nil, .asterism, "Aqr", 20.983, -12.633, 9.0),
        DeepSkyObject(74, "Phantom Galaxy", .galaxy, "Psc", 1.611, 15.783, 9.4),
        DeepSkyObject(75, nil, .globularCluster, "Sgr", 20.101, -21.922, 8.5),
        DeepSkyObject(76, "Little Dumbbell Nebula", .planetaryNebula, "Per", 1.705, 51.575, 10.1),
        DeepSkyObject(77, "Cetus A", .galaxy, "Cet", 2.712, -0.013, 8.9),
        DeepSkyObject(78, nil, .nebula, "Ori", 5.779, 0.079, 8.3),
        DeepSkyObject(79, nil, .globularCluster, "Lep", 5.402, -24.524, 7.7),
        DeepSkyObject(80, nil, .globularCluster, "Sco", 16.284, -22.976, 7.3),
        DeepSkyObject(81, "Bode's Galaxy", .galaxy, "UMa", 9.926, 69.065, 6.9),
        DeepSkyObject(82, "Cigar Galaxy", .galaxy, "UMa", 9.931, 69.680, 8.4),
        DeepSkyObject(83, "Southern Pinwheel Galaxy", .galaxy, "Hya", 13.617, -29.866, 7.5),
        DeepSkyObject(84, nil, .galaxy, "Vir", 12.418, 12.887, 9.1),
        DeepSkyObject(85, nil, .galaxy, "Com", 12.424, 18.191, 9.1),
        DeepSkyObject(86, nil, .galaxy, "Vir", 12.437, 12.946, 8.9),
        DeepSkyObject(87, "Virgo A", .galaxy, "Vir", 12.514, 12.391, 8.6),
        DeepSkyObject(88, nil, .galaxy, "Com", 12.533, 14.420, 9.6),
        DeepSkyObject(89, nil, .galaxy, "Vir", 12.594, 12.556, 9.8),
        DeepSkyObject(90, nil, .galaxy, "Vir", 12.614, 13.163, 9.5),
        DeepSkyObject(91, nil, .galaxy, "Com", 12.590, 14.496, 10.2),
        DeepSkyObject(92, nil, .globularCluster, "Her", 17.285, 43.136, 6.3),
        DeepSkyObject(93, nil, .openCluster, "Pup", 7.742, -23.853, 6.0),
        DeepSkyObject(94, "Croc's Eye Galaxy", .galaxy, "CVn", 12.849, 41.120, 8.2),
        DeepSkyObject(95, nil, .galaxy, "Leo", 10.732, 11.704, 9.7),
        DeepSkyObject(96, nil, .galaxy, "Leo", 10.779, 11.820, 9.2),
        DeepSkyObject(97, "Owl Nebula", .planetaryNebula, "UMa", 11.246, 55.019, 9.9),
        DeepSkyObject(98, nil, .galaxy, "Com", 12.230, 14.900, 10.1),
        DeepSkyObject(99, nil, .galaxy, "Com", 12.314, 14.417, 9.9),
        DeepSkyObject(100, nil, .galaxy, "Com", 12.382, 15.822, 9.3),
        DeepSkyObject(101, "Pinwheel Galaxy", .galaxy, "UMa", 14.053, 54.349, 7.9),
        DeepSkyObject(102, "Spindle Galaxy", .galaxy, "Dra", 15.108, 55.763, 9.9),
        DeepSkyObject(103, nil, .openCluster, "Cas", 1.556, 60.658, 7.4),
        DeepSkyObject(104, "Sombrero Galaxy", .galaxy, "Vir", 12.667, -11.623, 8.0),
        DeepSkyObject(105, nil, .galaxy, "Leo", 10.797, 12.582, 9.3),
        DeepSkyObject(106, nil, .galaxy, "CVn", 12.316, 47.304, 8.4),
        DeepSkyObject(107, nil, .globularCluster, "Oph", 16.542, -13.054, 7.9),
        DeepSkyObject(108, nil, .galaxy, "UMa", 11.191, 55.674, 10.0),
        DeepSkyObject(109, nil, .galaxy, "UMa", 11.960, 53.375, 9.8),
        DeepSkyObject(110, nil, .galaxy, "And", 0.673, 41.685, 8.1),
    ]

    static let objectsByNumber: [Int: DeepSkyObject] =
        Dictionary(uniqueKeysWithValues: objects.map { ($0.messierNumber, $0) })
}
