//
//  ConstellationCatalog.swift
//  AstroSky
//
//  Constellation names and stick-figure line definitions. Lines reference
//  stars in `StarCatalog` by key; unresolved references are ignored, so the
//  figures degrade gracefully if the star list changes.
//

import Foundation

struct Constellation: Identifiable, Sendable {
    /// IAU three-letter abbreviation, e.g. "UMa".
    let abbreviation: String
    let name: String
    /// Pairs of star keys defining the stick figure.
    let lines: [(String, String)]

    var id: String { "con.\(abbreviation)" }

    /// Resolved line segments as star pairs.
    var starPairs: [(Star, Star)] {
        lines.compactMap { pair in
            guard let a = StarCatalog.starsByKey[pair.0],
                  let b = StarCatalog.starsByKey[pair.1] else { return nil }
            return (a, b)
        }
    }

    /// Approximate center of the figure (mean of member star vectors).
    var centerJ2000: EquatorialCoordinates? {
        let keys = Set(lines.flatMap { [$0.0, $0.1] })
        let stars = keys.compactMap { StarCatalog.starsByKey[$0] }
        guard !stars.isEmpty else { return nil }
        var sum = SIMD3<Double>.zero
        for star in stars { sum += star.equatorialJ2000.unitVector }
        let v = sum / Double(stars.count)
        let length = (v.x * v.x + v.y * v.y + v.z * v.z).squareRoot()
        guard length > 0 else { return nil }
        let n = v / length
        return EquatorialCoordinates(rightAscension: atan2(n.y, n.x), declination: asin(n.z))
    }
}

enum ConstellationCatalog {
    static func fullName(forAbbreviation abbreviation: String) -> String {
        names[abbreviation] ?? abbreviation
    }

    /// Full names for every abbreviation used anywhere in the catalogs.
    static let names: [String: String] = [
        "And": "Andromeda", "Aqr": "Aquarius", "Aql": "Aquila", "Ari": "Aries",
        "Aur": "Auriga", "Boo": "Boötes", "CMa": "Canis Major", "CMi": "Canis Minor",
        "Cap": "Capricornus", "Car": "Carina", "Cas": "Cassiopeia", "Cen": "Centaurus",
        "Cep": "Cepheus", "Cet": "Cetus", "Cnc": "Cancer", "Com": "Coma Berenices",
        "CVn": "Canes Venatici",
        "CrB": "Corona Borealis", "Crv": "Corvus", "Cru": "Crux", "Cyg": "Cygnus",
        "Del": "Delphinus", "Dor": "Dorado", "Dra": "Draco", "Eri": "Eridanus",
        "Gem": "Gemini", "Gru": "Grus", "Her": "Hercules", "Hya": "Hydra",
        "Leo": "Leo", "Lep": "Lepus", "Lib": "Libra", "Lyr": "Lyra",
        "Mon": "Monoceros", "Oph": "Ophiuchus", "Ori": "Orion", "Pav": "Pavo",
        "Peg": "Pegasus", "Per": "Perseus", "Phe": "Phoenix", "PsA": "Piscis Austrinus",
        "Psc": "Pisces", "Pup": "Puppis", "Sge": "Sagitta", "Sgr": "Sagittarius",
        "Sco": "Scorpius", "Sct": "Scutum", "Ser": "Serpens", "Tau": "Taurus",
        "TrA": "Triangulum Australe", "Tri": "Triangulum", "UMa": "Ursa Major",
        "UMi": "Ursa Minor", "Vel": "Vela", "Vir": "Virgo", "Vul": "Vulpecula",
        // Remaining IAU constellations (used by the Caldwell / NGC catalogs).
        "Ant": "Antlia", "Aps": "Apus", "Ara": "Ara", "Cae": "Caelum",
        "Cam": "Camelopardalis", "Cha": "Chamaeleon", "Cir": "Circinus", "Col": "Columba",
        "CrA": "Corona Australis", "Crt": "Crater", "Equ": "Equuleus", "For": "Fornax",
        "Hor": "Horologium", "Hyi": "Hydrus", "Ind": "Indus", "Lac": "Lacerta",
        "LMi": "Leo Minor", "Lup": "Lupus", "Lyn": "Lynx", "Men": "Mensa",
        "Mic": "Microscopium", "Mus": "Musca", "Nor": "Norma", "Oct": "Octans",
        "Pic": "Pictor", "Pyx": "Pyxis", "Ret": "Reticulum", "Scl": "Sculptor",
        "Sex": "Sextans", "Tel": "Telescopium", "Tuc": "Tucana", "Vol": "Volans",
    ]

    static let constellations: [Constellation] = [
        Constellation(abbreviation: "UMa", name: "Ursa Major", lines: [
            ("dubhe", "merak"), ("merak", "phecda"), ("phecda", "megrez"),
            ("megrez", "dubhe"), ("megrez", "alioth"), ("alioth", "mizar"), ("mizar", "alkaid"),
        ]),
        Constellation(abbreviation: "UMi", name: "Ursa Minor", lines: [
            ("polaris", "yildun"), ("yildun", "epsumi"), ("epsumi", "zetumi"),
            ("zetumi", "kochab"), ("kochab", "pherkad"), ("pherkad", "etaumi"), ("etaumi", "zetumi"),
        ]),
        Constellation(abbreviation: "Cas", name: "Cassiopeia", lines: [
            ("caph", "schedar"), ("schedar", "navi"), ("navi", "ruchbah"), ("ruchbah", "segin"),
        ]),
        Constellation(abbreviation: "Cep", name: "Cepheus", lines: [
            ("alderamin", "alfirk"), ("alfirk", "errai"), ("errai", "iotcep"),
            ("iotcep", "zetcep"), ("zetcep", "delcep"), ("delcep", "zetcep"),
            ("zetcep", "alderamin"), ("alfirk", "iotcep"),
        ]),
        Constellation(abbreviation: "Dra", name: "Draco", lines: [
            ("rastaban", "eltanin"), ("eltanin", "xidra"), ("xidra", "nudra"), ("nudra", "rastaban"),
            ("xidra", "deldra"), ("deldra", "epsdra"), ("epsdra", "chidra"), ("chidra", "zetdra"),
            ("zetdra", "etadra"), ("etadra", "thedra"), ("thedra", "edasich"),
            ("edasich", "thuban"), ("thuban", "kapdra"), ("kapdra", "lamdra"),
        ]),
        Constellation(abbreviation: "Cyg", name: "Cygnus", lines: [
            ("deneb", "sadr"), ("sadr", "albireo"), ("delcyg", "sadr"), ("sadr", "aljanah"),
        ]),
        Constellation(abbreviation: "Lyr", name: "Lyra", lines: [
            ("vega", "zetlyr"), ("zetlyr", "sheliak"), ("sheliak", "sulafat"),
            ("sulafat", "dellyr"), ("dellyr", "zetlyr"),
        ]),
        Constellation(abbreviation: "Aql", name: "Aquila", lines: [
            ("tarazed", "altair"), ("altair", "alshain"), ("altair", "delaql"),
            ("delaql", "zetaql"), ("delaql", "lamaql"), ("delaql", "theaql"),
        ]),
        Constellation(abbreviation: "Del", name: "Delphinus", lines: [
            ("sualocin", "gamdel"), ("gamdel", "deldel"), ("deldel", "rotanev"),
            ("rotanev", "sualocin"), ("rotanev", "aldulfin"),
        ]),
        Constellation(abbreviation: "Ori", name: "Orion", lines: [
            ("betelgeuse", "bellatrix"), ("bellatrix", "mintaka"), ("mintaka", "alnilam"),
            ("alnilam", "alnitak"), ("alnitak", "betelgeuse"), ("alnitak", "saiph"),
            ("saiph", "rigel"), ("rigel", "mintaka"), ("betelgeuse", "meissa"), ("meissa", "bellatrix"),
        ]),
        Constellation(abbreviation: "CMa", name: "Canis Major", lines: [
            ("sirius", "mirzam"), ("sirius", "wezen"), ("wezen", "adhara"), ("wezen", "aludra"),
        ]),
        Constellation(abbreviation: "CMi", name: "Canis Minor", lines: [
            ("procyon", "gomeisa"),
        ]),
        Constellation(abbreviation: "Gem", name: "Gemini", lines: [
            ("castor", "pollux"), ("castor", "mebsuta"), ("mebsuta", "tejat"),
            ("tejat", "propus"), ("pollux", "wasat"), ("wasat", "alhena"),
        ]),
        Constellation(abbreviation: "Tau", name: "Taurus", lines: [
            ("aldebaran", "zettau"), ("epstau", "elnath"), ("gamtau", "aldebaran"),
            ("gamtau", "epstau"), ("gamtau", "lamtau"), ("aldebaran", "alcyone"),
        ]),
        Constellation(abbreviation: "Aur", name: "Auriga", lines: [
            ("capella", "menkalinan"), ("menkalinan", "theaur"), ("theaur", "elnath"),
            ("elnath", "iotaur"), ("iotaur", "capella"),
        ]),
        Constellation(abbreviation: "Per", name: "Perseus", lines: [
            ("gamper", "mirfak"), ("mirfak", "delper"), ("delper", "epsper"),
            ("epsper", "zetper"), ("mirfak", "algol"),
        ]),
        Constellation(abbreviation: "And", name: "Andromeda", lines: [
            ("alpheratz", "deland"), ("deland", "mirach"), ("mirach", "almach"),
        ]),
        Constellation(abbreviation: "Peg", name: "Pegasus", lines: [
            ("markab", "scheat"), ("scheat", "alpheratz"), ("alpheratz", "algenib"),
            ("algenib", "markab"), ("enif", "thepeg"), ("thepeg", "homam"), ("homam", "markab"),
        ]),
        Constellation(abbreviation: "Leo", name: "Leo", lines: [
            ("epsleo", "rasalas"), ("rasalas", "adhafera"), ("adhafera", "algieba"),
            ("algieba", "etaleo"), ("etaleo", "regulus"), ("algieba", "zosma"),
            ("zosma", "denebola"), ("denebola", "chertan"), ("chertan", "regulus"),
        ]),
        Constellation(abbreviation: "Vir", name: "Virgo", lines: [
            ("betvir", "etavir"), ("etavir", "porrima"), ("porrima", "auva"),
            ("auva", "vindemiatrix"), ("porrima", "spica"), ("spica", "heze"),
        ]),
        Constellation(abbreviation: "Boo", name: "Boötes", lines: [
            ("arcturus", "izar"), ("izar", "delboo"), ("delboo", "nekkar"),
            ("nekkar", "seginus"), ("seginus", "arcturus"), ("arcturus", "muphrid"),
        ]),
        Constellation(abbreviation: "CrB", name: "Corona Borealis", lines: [
            ("thecrb", "nusakan"), ("nusakan", "alphecca"), ("alphecca", "gamcrb"),
            ("gamcrb", "delcrb"), ("delcrb", "epscrb"),
        ]),
        Constellation(abbreviation: "Her", name: "Hercules", lines: [
            ("etaher", "zether"), ("zether", "epsher"), ("epsher", "piher"), ("piher", "etaher"),
            ("zether", "kornephoros"), ("epsher", "sarin"), ("sarin", "rasalgethi"),
        ]),
        Constellation(abbreviation: "Oph", name: "Ophiuchus", lines: [
            ("rasalhague", "cebalrai"), ("cebalrai", "sabik"), ("sabik", "zetoph"),
            ("zetoph", "yedposterior"), ("yedposterior", "yedprior"), ("yedprior", "kapoph"),
            ("kapoph", "rasalhague"),
        ]),
        Constellation(abbreviation: "Sco", name: "Scorpius", lines: [
            ("acrab", "dschubba"), ("dschubba", "pisco"), ("dschubba", "sigsco"),
            ("sigsco", "antares"), ("antares", "tausco"), ("tausco", "larawag"),
            ("larawag", "mu1sco"), ("mu1sco", "zet2sco"), ("zet2sco", "etasco"),
            ("etasco", "sargas"), ("sargas", "iot1sco"), ("iot1sco", "girtab"),
            ("girtab", "shaula"), ("shaula", "lesath"),
        ]),
        Constellation(abbreviation: "Sgr", name: "Sagittarius", lines: [
            ("alnasl", "kausmedia"), ("kausmedia", "kausaustralis"), ("kausmedia", "kausborealis"),
            ("kausborealis", "phisgr"), ("phisgr", "nunki"), ("nunki", "tausgr"),
            ("tausgr", "ascella"), ("ascella", "phisgr"), ("ascella", "kausaustralis"),
        ]),
        Constellation(abbreviation: "Cap", name: "Capricornus", lines: [
            ("algedi", "dabih"), ("dabih", "denebalgedi"), ("denebalgedi", "nashira"),
        ]),
        Constellation(abbreviation: "Aqr", name: "Aquarius", lines: [
            ("sadalmelik", "sadalsuud"), ("sadalmelik", "gamaqr"),
        ]),
        Constellation(abbreviation: "Ari", name: "Aries", lines: [
            ("hamal", "sheratan"), ("sheratan", "mesarthim"),
        ]),
        Constellation(abbreviation: "Lib", name: "Libra", lines: [
            ("zubenelgenubi", "zubeneschamali"), ("zubeneschamali", "gamlib"),
            ("gamlib", "zubenelgenubi"),
        ]),
        Constellation(abbreviation: "Crv", name: "Corvus", lines: [
            ("alchiba", "minkar"), ("minkar", "gienahcrv"), ("gienahcrv", "algorab"),
            ("algorab", "kraz"), ("kraz", "minkar"),
        ]),
        Constellation(abbreviation: "Cru", name: "Crux", lines: [
            ("acrux", "gacrux"), ("mimosa", "imai"),
        ]),
        Constellation(abbreviation: "Cen", name: "Centaurus", lines: [
            ("rigilkent", "hadar"), ("hadar", "epscen"), ("epscen", "muhlifain"),
            ("muhlifain", "delcen"), ("epscen", "zetcen"), ("zetcen", "etacen"),
            ("etacen", "menkent"),
        ]),
        Constellation(abbreviation: "TrA", name: "Triangulum Australe", lines: [
            ("atria", "bettra"), ("bettra", "gamtra"), ("gamtra", "atria"),
        ]),
        Constellation(abbreviation: "Gru", name: "Grus", lines: [
            ("alnair", "tiaki"),
        ]),
        Constellation(abbreviation: "Car", name: "Carina", lines: [
            ("canopus", "avior"), ("avior", "aspidiske"), ("aspidiske", "miaplacidus"),
        ]),
    ]

    static let constellationsByAbbreviation: [String: Constellation] =
        Dictionary(uniqueKeysWithValues: constellations.map { ($0.abbreviation, $0) })
}
