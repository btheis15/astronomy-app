//
//  CatalogView.swift
//  AstroSky
//
//  Browsable catalog: planets, stars, Messier objects, constellations
//  and live satellites, with live altitude readouts.
//

import SwiftUI

struct CatalogView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        ObjectListView(title: "Solar System", objects: solarSystemObjects)
                    } label: {
                        Label("Solar System", systemImage: "sun.max.fill")
                    }
                    NavigationLink {
                        ObjectListView(title: "Bright Stars",
                                       objects: appState.catalog.stars.prefix(300).map { $0 })
                    } label: {
                        Label("Bright Stars", systemImage: "star.fill")
                    }
                    NavigationLink {
                        ObjectListView(title: "Messier Objects",
                                       objects: appState.catalog.deepSky)
                    } label: {
                        Label("Messier Objects", systemImage: "sparkles")
                    }
                    NavigationLink {
                        ConstellationListView()
                    } label: {
                        Label("Constellations", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                } header: {
                    Text("Catalog")
                }

                Section {
                    NavigationLink {
                        ObjectListView(title: "Featured Satellites",
                                       objects: appState.satelliteService.featured)
                    } label: {
                        Label("Featured Satellites", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    NavigationLink {
                        ObjectListView(title: "Starlink",
                                       objects: appState.satelliteService.starlinkForDisplay)
                    } label: {
                        Label("Starlink", systemImage: "wifi")
                    }
                } header: {
                    Text("Satellites")
                } footer: {
                    satelliteFooter
                }
            }
            .navigationTitle("Catalog")
        }
    }

    private var solarSystemObjects: [any CelestialObject] {
        var objects: [any CelestialObject] = [appState.catalog.sun, appState.catalog.moon]
        objects.append(contentsOf: appState.catalog.planets.map { $0 as any CelestialObject })
        return objects
    }

    private var satelliteFooter: some View {
        Group {
            switch appState.satelliteService.state {
            case .loaded(let date) where date > .distantPast:
                Text("Orbital elements from Celestrak · updated \(date.formatted(.relative(presentation: .named)))")
            case .loading:
                Text("Updating orbital elements from Celestrak…")
            case .failed(let message):
                Text(message)
            default:
                Text("Orbital elements from Celestrak")
            }
        }
    }
}

// MARK: - Generic object list

struct ObjectListView: View {
    @Environment(AppState.self) private var appState
    let title: String
    let objects: [any CelestialObject]
    @State private var query = ""

    private var filtered: [any CelestialObject] {
        guard !query.isEmpty else { return objects }
        return objects.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.subtitle.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        List(filtered, id: \.id) { object in
            NavigationLink {
                ObjectDetailView(object: object)
            } label: {
                CatalogRow(object: object)
            }
        }
        .navigationTitle(title)
        .searchable(text: $query)
        .overlay {
            if objects.isEmpty {
                ContentUnavailableView("Nothing here yet",
                                       systemImage: "antenna.radiowaves.left.and.right.slash",
                                       description: Text("Satellite data loads from Celestrak when online."))
            }
        }
    }
}

struct CatalogRow: View {
    @Environment(AppState.self) private var appState
    let object: any CelestialObject

    var body: some View {
        let horizontal = object.horizontal(julianDate: appState.skyJulianDate,
                                           observer: appState.observer)
        HStack {
            Image(systemName: object.kind.iconSystemName)
                .foregroundStyle(.yellow)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(object.name)
                Text(object.subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let magnitude = object.magnitude {
                    Text("mag \(AstroFormat.magnitude(magnitude))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Circle()
                    .fill(horizontal.isAboveHorizon ? Color.green : Color.gray.opacity(0.4))
                    .frame(width: 8, height: 8)
            }
        }
    }
}

// MARK: - Constellations

struct ConstellationListView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List(ConstellationCatalog.constellations) { constellation in
            HStack {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .foregroundStyle(.indigo)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(constellation.name)
                    Text("\(constellation.starPairs.count) figure lines · \(constellation.abbreviation)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let center = constellation.centerJ2000 {
                    let horizontal = CoordinateTransforms.horizontal(
                        of: CoordinateTransforms.precessFromJ2000(center, julianDate: appState.skyJulianDate),
                        julianDate: appState.skyJulianDate,
                        observer: appState.observer)
                    Circle()
                        .fill(horizontal.isAboveHorizon ? Color.green : Color.gray.opacity(0.4))
                        .frame(width: 8, height: 8)
                }
            }
        }
        .navigationTitle("Constellations")
    }
}
