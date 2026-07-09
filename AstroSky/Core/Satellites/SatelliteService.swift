//
//  SatelliteService.swift
//  AstroSky
//
//  Fetches live TLEs from Celestrak, caches them on disk, and exposes the
//  resulting satellites to the app. Works offline from the cache; degrades
//  gracefully to "no satellites" when nothing has ever been fetched.
//

import Foundation
import Observation

@MainActor
@Observable
final class SatelliteService {
    enum FetchState: Equatable {
        case idle
        case loading
        case loaded(Date)
        case failed(String)
    }

    /// Celestrak groups the app tracks. "visual" is the list of naked-eye
    /// satellites (ISS, Hubble, Tiangong, bright rocket bodies…).
    static let groups = ["stations", "visual", "starlink"]

    /// Refetch interval — TLEs go stale after a day or two.
    static let refreshInterval: TimeInterval = 6 * 3600

    private(set) var satellites: [Satellite] = []
    private(set) var state: FetchState = .idle

    /// Satellites of the bright/featured kind (non-Starlink).
    var featured: [Satellite] { satellites.filter { !$0.isStarlink } }
    var starlink: [Satellite] { satellites.filter(\.isStarlink) }

    /// Cap the Starlink render set: thousands of nearly identical satellites
    /// would clutter the sky and burn CPU. The subset is stable (sorted by
    /// catalog number).
    var starlinkForDisplay: [Satellite] {
        Array(starlink.sorted { $0.tle.catalogNumber < $1.tle.catalogNumber }.prefix(300))
    }

    func satellite(withID id: String) -> Satellite? {
        satellites.first { $0.id == id }
    }

    func search(_ query: String) -> [Satellite] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        return satellites
            .filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
            .prefix(50)
            .map { $0 }
    }

    // MARK: Loading

    /// Load from cache immediately, then refresh from the network if stale.
    func start() async {
        if let cached = loadFromCache() {
            apply(tleSets: cached.sets)
            state = .loaded(cached.date)
            if Date().timeIntervalSince(cached.date) < Self.refreshInterval {
                return
            }
        }
        await refresh()
    }

    func refresh() async {
        state = .loading
        var fetched: [String: String] = [:]
        var firstError: String?

        await withTaskGroup(of: (String, String?).self) { taskGroup in
            for group in Self.groups {
                taskGroup.addTask {
                    let text = try? await Self.fetchGroup(group)
                    return (group, text)
                }
            }
            for await (group, text) in taskGroup {
                if let text {
                    fetched[group] = text
                } else if firstError == nil {
                    firstError = "Couldn't reach Celestrak for “\(group)”"
                }
            }
        }

        guard !fetched.isEmpty else {
            // Keep whatever we had (cache or nothing).
            state = satellites.isEmpty
                ? .failed(firstError ?? "Satellite data unavailable — check your connection")
                : .loaded(Date.distantPast)
            return
        }

        saveToCache(sets: fetched)
        apply(tleSets: fetched)
        state = .loaded(Date())
    }

    private func apply(tleSets: [String: String]) {
        var seen = Set<Int>()
        var result: [Satellite] = []
        for group in Self.groups {
            guard let text = tleSets[group] else { continue }
            for tle in TLEParser.parse(text: text) {
                guard !seen.contains(tle.catalogNumber) else { continue }
                guard let satellite = Satellite(tle: tle, group: group) else { continue }
                seen.insert(tle.catalogNumber)
                result.append(satellite)
            }
        }
        satellites = result
    }

    private static func fetchGroup(_ group: String) async throws -> String {
        var components = URLComponents(string: "https://celestrak.org/NORAD/elements/gp.php")!
        components.queryItems = [
            URLQueryItem(name: "GROUP", value: group),
            URLQueryItem(name: "FORMAT", value: "tle"),
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let text = String(data: data, encoding: .utf8) else {
            throw URLError(.badServerResponse)
        }
        return text
    }

    // MARK: Cache

    private struct CachePayload: Codable {
        var date: Date
        var sets: [String: String]
    }

    private nonisolated static var cacheURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("tle-cache.json")
    }

    private func loadFromCache() -> (date: Date, sets: [String: String])? {
        guard let data = try? Data(contentsOf: Self.cacheURL),
              let payload = try? JSONDecoder().decode(CachePayload.self, from: data) else {
            return nil
        }
        return (payload.date, payload.sets)
    }

    private func saveToCache(sets: [String: String]) {
        let payload = CachePayload(date: Date(), sets: sets)
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: Self.cacheURL, options: .atomic)
        }
    }

}
