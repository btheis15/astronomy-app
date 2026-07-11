//
//  Intents.swift
//  AstroSky
//
//  App Intents (Siri / Shortcuts): quick spoken answers computed from the
//  astronomy engine for the user's last-known location.
//

import AppIntents
import Foundation

// MARK: - Moon phase

struct MoonPhaseIntent: AppIntent {
    static let title: LocalizedStringResource = "Moon Phase"
    static let description = IntentDescription("Tells you the current Moon phase and illumination.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let phase = MoonEphemeris.phase(julianDate: AstroTime.julianDate(Date()))
        let percent = Int((phase.illuminatedFraction * 100).rounded())
        return .result(dialog: "The Moon is a \(phase.phaseName), \(percent)% illuminated.")
    }
}

// MARK: - Planet visibility

enum PlanetChoice: String, AppEnum {
    case mercury, venus, mars, jupiter, saturn, uranus, neptune

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Planet")
    static let caseDisplayRepresentations: [PlanetChoice: DisplayRepresentation] = [
        .mercury: "Mercury", .venus: "Venus", .mars: "Mars", .jupiter: "Jupiter",
        .saturn: "Saturn", .uranus: "Uranus", .neptune: "Neptune",
    ]

    var planet: Planet {
        switch self {
        case .mercury: .mercury
        case .venus: .venus
        case .mars: .mars
        case .jupiter: .jupiter
        case .saturn: .saturn
        case .uranus: .uranus
        case .neptune: .neptune
        }
    }
}

struct PlanetVisibilityIntent: AppIntent {
    static let title: LocalizedStringResource = "Is a Planet Visible Tonight"
    static let description = IntentDescription("Checks whether a planet rises high enough to see tonight.")

    @Parameter(title: "Planet")
    var planet: PlanetChoice

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let observer = Observer.lastKnown
        let name = planet.planet.name

        // Sample altitude over the next 12 hours; report the best moment.
        var bestAltitude = -90.0
        var bestDate = Date()
        for minutes in stride(from: 0.0, through: 12 * 60, by: 20) {
            let date = Date().addingTimeInterval(minutes * 60)
            let jd = AstroTime.julianDate(date)
            let alt = PlanetObject(planet: planet.planet)
                .horizontal(julianDate: jd, observer: observer).altitudeDegrees
            if alt > bestAltitude { bestAltitude = alt; bestDate = date }
        }

        if bestAltitude < 5 {
            return .result(dialog: "\(name) stays below the horizon over the next 12 hours from your location.")
        }
        let time = bestDate.formatted(date: .omitted, time: .shortened)
        return .result(dialog: "Yes — \(name) climbs to about \(Int(bestAltitude))° altitude, best around \(time).")
    }
}

// MARK: - Next ISS pass

struct NextISSPassIntent: AppIntent {
    static let title: LocalizedStringResource = "Next ISS Pass"
    static let description = IntentDescription("Finds the next visible pass of the International Space Station.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let observer = Observer.lastKnown
        let satellites = SatelliteService.cachedSatellites()
        guard let iss = satellites.first(where: { $0.isISS }) else {
            return .result(dialog: "Open AstroSky once while online so I can download the ISS orbit, then ask again.")
        }
        let passes = iss.passes(observer: observer, startingAt: Date(), hours: 48)
        guard let next = passes.first(where: { $0.isVisible }) ?? passes.first else {
            return .result(dialog: "No ISS passes are predicted over the next 48 hours from your location.")
        }
        let day = next.start.formatted(date: .abbreviated, time: .shortened)
        let peak = Int((next.maxAltitude * 180 / .pi).rounded())
        let visibility = next.isVisible ? "a visible pass" : "a pass (not sunlit)"
        return .result(dialog: "The next ISS pass is \(visibility) on \(day), peaking near \(peak)° altitude.")
    }
}

// MARK: - Shortcuts

struct AstroSkyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: MoonPhaseIntent(),
                    phrases: ["What's the moon phase in \(.applicationName)",
                              "\(.applicationName) moon phase"],
                    shortTitle: "Moon Phase", systemImageName: "moon.fill")
        AppShortcut(intent: NextISSPassIntent(),
                    phrases: ["When is the next ISS pass in \(.applicationName)",
                              "\(.applicationName) next space station pass"],
                    shortTitle: "Next ISS Pass", systemImageName: "antenna.radiowaves.left.and.right")
        AppShortcut(intent: PlanetVisibilityIntent(),
                    phrases: ["Is a planet visible tonight in \(.applicationName)",
                              "\(.applicationName) planet visibility"],
                    shortTitle: "Planet Visibility", systemImageName: "circle.fill")
    }
}
