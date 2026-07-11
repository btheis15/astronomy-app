//
//  HYGCatalogLoader.swift
//  AstroSky
//
//  Optional deep star catalog. If a file named `hygdata.csv` (the HYG
//  database, https://github.com/astronexus/HYG-Database) is present in the
//  app bundle, the AR sky is populated with thousands of stars instead of
//  the embedded bright-star list. See the README for instructions.
//
//  Expected columns (HYG v3/v4 header names): ra (hours), dec (degrees),
//  mag, ci (B−V), proper (name), con (constellation), dist (parsecs).
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.astrosky", category: "ephemeris")

enum HYGCatalogLoader {
    static let bundledFileName = "hygdata"

    /// Loads the HYG CSV from the bundle if present.
    /// - Parameter magnitudeLimit: faintest magnitude to keep (6.5 by default,
    ///   the naked-eye limit; keeps memory and mesh sizes sane).
    /// - Returns: stars sorted brightest-first, or nil when no CSV is bundled.
    static func loadIfAvailable(magnitudeLimit: Double = 6.5) -> [Star]? {
        guard let url = Bundle.main.url(forResource: bundledFileName, withExtension: "csv") else {
            logger.debug("HYG catalog file not found in bundle")
            return nil
        }
        do {
            let contents = try String(contentsOf: url, encoding: .utf8)
            return parse(csv: contents, magnitudeLimit: magnitudeLimit)
        } catch {
            logger.error("Failed to load HYG catalog: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func parse(csv: String, magnitudeLimit: Double) -> [Star] {
        var lines = csv.split(separator: "\n", omittingEmptySubsequences: true)[...]
        guard let headerLine = lines.popFirst() else { return [] }
        let header = headerLine.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }

        func index(of column: String) -> Int? { header.firstIndex(of: column) }
        guard let raIdx = index(of: "ra"),
              let decIdx = index(of: "dec"),
              let magIdx = index(of: "mag") else { return [] }
        let ciIdx = index(of: "ci")
        let properIdx = index(of: "proper")
        let conIdx = index(of: "con")
        let distIdx = index(of: "dist")
        let idIdx = index(of: "id")

        var stars: [Star] = []
        stars.reserveCapacity(16_000)

        for line in lines {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count > max(raIdx, decIdx, magIdx),
                  let ra = Double(fields[raIdx]),
                  let dec = Double(fields[decIdx]),
                  let mag = Double(fields[magIdx]),
                  mag <= magnitudeLimit else { continue }

            // The HYG catalog lists the Sun as the first entry; skip it.
            if mag < -20 { continue }

            let ci = ciIdx.flatMap { $0 < fields.count ? Double(fields[$0]) : nil } ?? 0.5
            let proper = properIdx.flatMap { $0 < fields.count ? String(fields[$0]) : nil }
            let con = conIdx.flatMap { $0 < fields.count ? String(fields[$0]) : nil } ?? ""
            let distParsecs = distIdx.flatMap { $0 < fields.count ? Double(fields[$0]) : nil }
            let hygID = idIdx.flatMap { $0 < fields.count ? String(fields[$0]) : nil } ?? "\(stars.count)"

            let name = (proper?.isEmpty ?? true) ? nil : proper
            let lightYears = distParsecs.map { $0 * 3.26156 }
            stars.append(Star("hyg\(hygID)",
                              name: name,
                              bayer: nil,
                              con: con,
                              ra: ra,
                              dec: dec,
                              mag: mag,
                              bv: ci,
                              ly: lightYears))
        }
        return stars.sorted { $0.visualMagnitude < $1.visualMagnitude }
    }
}
