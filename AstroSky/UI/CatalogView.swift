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
                    Label("Observing Log", systemImage: "book.closed")
                        .tag(CatalogSelection.observingLog)
                    Label("Solar System Orrery", systemImage: "circle.hexagongrid.fill")
                        .tag(CatalogSelection.orrery)
                    Label("Observe Tonight · your telescope", systemImage: "eyeglasses")
                        .tag(CatalogSelection.observeTonight)
                }

                Section {
                    Label("Solar System", systemImage: "sun.max.fill")
                        .tag(CatalogSelection.solarSystem)
                    Label("Bright Stars", systemImage: "star.fill")
                        .tag(CatalogSelection.brightStars)
                    Label("Messier Objects", systemImage: "sparkles")
                        .tag(CatalogSelection.messier)
                    Label("Caldwell Objects", systemImage: "sparkles")
                        .tag(CatalogSelection.caldwell)
                    Label("NGC Highlights", systemImage: "sparkles")
                        .tag(CatalogSelection.ngc)
                    Label("Constellations", systemImage: "point.3.connected.trianglepath.dotted")
                        .tag(CatalogSelection.constellations)
                } header: {
                    Text("Catalog")
                }

                Section {
                    Label("Featured Satellites", systemImage: "antenna.radiowaves.left.and.right")
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
            ObjectListView(title: "Solar System", objects: solarSystemObjects)
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

    private var solarSystemObjects: [any CelestialObject] {
        var objects: [any CelestialObject] = [appState.catalog.sun, appState.catalog.moon]
        objects.append(contentsOf: appState.catalog.planets.map { $0 as any CelestialObject })
        objects.append(contentsOf: appState.catalog.minorBodies.map { $0 as any CelestialObject })
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
            if object.kind == .satellite {
                Button {
                    appState.toggleFavoriteSatellite(object.id)
                } label: {
                    Image(systemName: appState.isFavoriteSatellite(object.id) ? "star.fill" : "star")
                        .foregroundStyle(appState.isFavoriteSatellite(object.id) ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)
            }
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
            NavigationLink {
                ConstellationDetailView(constellation: constellation)
            } label: {
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
        }
        .navigationTitle("Constellations")
    }
}

/// Facts about a constellation plus its member stars. Constellations aren't
/// `CelestialObject`s themselves, so drill-down and "Find in AR" reuse the
/// figure's stars, which are.
struct ConstellationDetailView: View {
    @Environment(AppState.self) private var appState
    let constellation: Constellation

    /// Unique member stars of the stick figure, brightest first.
    private var memberStars: [Star] {
        var seen = Set<String>()
        return constellation.starPairs
            .flatMap { [$0.0, $0.1] }
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.visualMagnitude < $1.visualMagnitude }
    }

    var body: some View {
        List {
            Section {
                if let center = constellation.centerJ2000 {
                    let horizontal = CoordinateTransforms.horizontal(
                        of: CoordinateTransforms.precessFromJ2000(center, julianDate: appState.skyJulianDate),
                        julianDate: appState.skyJulianDate,
                        observer: appState.observer)
                    HStack {
                        Label(horizontal.isAboveHorizon ? "Up now" : "Below horizon",
                              systemImage: horizontal.isAboveHorizon ? "eye" : "eye.slash")
                            .foregroundStyle(horizontal.isAboveHorizon ? .green : .secondary)
                        Spacer()
                        Text("\(AstroFormat.degrees(horizontal.altitude)) · \(horizontal.compassDirection)")
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
                if let brightest = memberStars.first {
                    Button {
                        appState.select(brightest)
                        appState.guideTargetID = brightest.id
                        appState.skyTabRequested = true
                    } label: {
                        Label("Find in AR", systemImage: "location.viewfinder")
                    }
                }
            } header: {
                Text("\(constellation.starPairs.count) figure lines · \(constellation.abbreviation)")
            }

            if !memberStars.isEmpty {
                Section("Stars in this figure") {
                    ForEach(memberStars, id: \.id) { star in
                        NavigationLink {
                            ObjectDetailView(object: star)
                        } label: {
                            CatalogRow(object: star)
                        }
                    }
                }
            }
        }
        .navigationTitle(constellation.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
