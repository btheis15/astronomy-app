//
//  CatalogView.swift
//  AstroSky
//
//  Browsable catalog: planets, stars, Messier objects, constellations
//  and live satellites, with live altitude readouts.
//

import SwiftUI

/// Top-level catalog destinations. Hashable so the sidebar can drive an
/// adaptive `NavigationSplitView` selection (two columns on iPad / landscape,
/// collapsing to a push navigation on iPhone portrait). Favorites are keyed by
/// object id and resolved from `AppState` when shown.
enum CatalogSelection: Hashable {
    case favorite(String)
    case observingLog, orrery, observeTonight
    case solarSystem, brightStars, messier, caldwell, ngc, constellations
    case featuredSatellites, starlink
}

struct CatalogView: View {
    @Environment(AppState.self) private var appState
    @State private var selection: CatalogSelection?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                if !appState.favoriteObjects.isEmpty {
                    Section("Favorites") {
                        ForEach(appState.favoriteObjects, id: \.id) { object in
                            CatalogRow(object: object)
                                .tag(CatalogSelection.favorite(object.id))
                        }
                    }
                }

                Section {
                    Label { Text("Solar System") } icon: { SunGlyph(size: 24) }
                        .tag(CatalogSelection.solarSystem)
                    Label { Text("Bright Stars") } icon: {
                        StarGlyph(magnitude: 0.2, colorIndexBV: 0.0, size: 24)
                    }
                        .tag(CatalogSelection.brightStars)
                    Label { Text("Messier Objects") } icon: { DeepSkyGlyph(type: .nebula, size: 24) }
                        .tag(CatalogSelection.messier)
                    Label { Text("Caldwell Objects") } icon: { DeepSkyGlyph(type: .galaxy, size: 24) }
                        .tag(CatalogSelection.caldwell)
                    Label { Text("NGC Highlights") } icon: { DeepSkyGlyph(type: .globularCluster, size: 24) }
                        .tag(CatalogSelection.ngc)
                    Label { Text("Constellations") } icon: { CatalogView.constellationCategoryGlyph }
                        .tag(CatalogSelection.constellations)
                } header: {
                    Text("Catalogs")
                }

                Section {
                    Label("Observing Log", systemImage: "book.closed")
                        .tag(CatalogSelection.observingLog)
                    Label("Orrery", systemImage: "circle.hexagongrid.fill")
                        .tag(CatalogSelection.orrery)
                } header: {
                    Text("Tools")
                }

                Section {
                    Label { Text("Featured Satellites") } icon: { SatelliteGlyph(size: 24) }
                        .tag(CatalogSelection.featuredSatellites)
                    Label("Starlink", systemImage: "wifi")
                        .tag(CatalogSelection.starlink)
                } header: {
                    Text("Satellites")
                } footer: {
                    satelliteFooter
                }
            }
            .navigationTitle("Catalog")
        } detail: {
            NavigationStack {
                detailView
            }
            .id(selection)
        }
    }

    /// Root content for the selected section. Inner views keep their own
    /// view-based `NavigationLink`s, which push within this detail stack.
    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .favorite(let id):
            if let object = appState.favoriteObjects.first(where: { $0.id == id }) {
                ObjectDetailView(object: object)
            } else {
                catalogPlaceholder
            }
        case .observingLog: ObservationLogView()
        case .orrery: OrreryView()
        case .observeTonight: ObserveTonightView()
        case .solarSystem:
            ObjectListView(title: "Solar System", objects: appState.catalog.solarSystemObjects)
        case .brightStars:
            ObjectListView(title: "Bright Stars",
                           objects: appState.catalog.stars.prefix(300).map { $0 })
        case .messier:
            ObjectListView(title: "Messier Objects", objects: MessierCatalog.objects)
        case .caldwell:
            ObjectListView(title: "Caldwell Objects", objects: CaldwellCatalog.objects)
        case .ngc:
            ObjectListView(title: "NGC Highlights", objects: NGCHighlights.objects)
        case .constellations: ConstellationListView()
        case .featuredSatellites:
            ObjectListView(title: "Featured Satellites",
                           objects: appState.satelliteService.featured)
        case .starlink:
            ObjectListView(title: "Starlink",
                           objects: appState.satelliteService.starlinkForDisplay)
        case nil:
            catalogPlaceholder
        }
    }

    private var catalogPlaceholder: some View {
        ContentUnavailableView("Select an item",
                               systemImage: "sparkles",
                               description: Text("Browse the sky catalog, your telescope targets and live satellites."))
    }

    /// Representative stick-figure for the Constellations category row (Orion).
    @ViewBuilder
    static var constellationCategoryGlyph: some View {
        if let orion = ConstellationCatalog.constellations.first(where: { $0.abbreviation == "Ori" })
            ?? ConstellationCatalog.constellations.first {
            ConstellationGlyph(constellation: orion, size: 24)
        } else {
            Image(systemName: "point.3.connected.trianglepath.dotted")
        }
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
