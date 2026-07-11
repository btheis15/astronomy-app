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
                    Label("Observe Tonight", systemImage: "eyeglasses")
                        .tag(CatalogSelection.observeTonight)
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
    @State private var isAboveHorizon = false

    private var positionKey: Int { Int(appState.skyJulianDate * 17280) }

    var body: some View {
        HStack {
            ObjectGlyph(object: object, size: 30)
                .frame(width: 34)
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
                    .fill(isAboveHorizon ? Color.green : Color.gray.opacity(0.4))
                    .frame(width: 8, height: 8)
            }
        }
        .task(id: positionKey) {
            let jd = appState.skyJulianDate
            let obs = appState.observer
            isAboveHorizon = object.horizontal(julianDate: jd, observer: obs).isAboveHorizon
        }
    }
}

// MARK: - Constellations

struct ConstellationListView: View {
    var body: some View {
        List(ConstellationCatalog.constellations) { constellation in
            NavigationLink {
                ConstellationDetailView(constellation: constellation)
            } label: {
                ConstellationRow(constellation: constellation)
            }
        }
        .navigationTitle("Constellations")
    }
}

private struct ConstellationRow: View {
    @Environment(AppState.self) private var appState
    let constellation: Constellation
    @State private var isAboveHorizon = false

    private var positionKey: Int { Int(appState.skyJulianDate * 17280) }

    var body: some View {
        HStack {
            ConstellationGlyph(constellation: constellation, size: 30)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(constellation.name)
                Text("\(constellation.starPairs.count) figure lines · \(constellation.abbreviation)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if constellation.centerJ2000 != nil {
                Circle()
                    .fill(isAboveHorizon ? Color.green : Color.gray.opacity(0.4))
                    .frame(width: 8, height: 8)
            }
        }
        .task(id: positionKey) {
            guard let center = constellation.centerJ2000 else { return }
            let jd = appState.skyJulianDate
            let obs = appState.observer
            isAboveHorizon = CoordinateTransforms.horizontal(
                of: CoordinateTransforms.precessFromJ2000(center, julianDate: jd),
                julianDate: jd, observer: obs).isAboveHorizon
        }
    }
}

/// Facts about a constellation plus its member stars. Constellations aren't
/// `CelestialObject`s themselves, so drill-down and "Find in AR" reuse the
/// figure's stars, which are.
struct ConstellationDetailView: View {
    @Environment(AppState.self) private var appState
    let constellation: Constellation
    @State private var isAboveHorizon = false
    @State private var altStr = "—"
    @State private var compassStr = "—"

    private var positionKey: Int { Int(appState.skyJulianDate * 17280) }

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
                VStack(spacing: 10) {
                    ConstellationGlyph(constellation: constellation, size: 132)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color(red: 0.04, green: 0.05, blue: 0.12))
                        )
                    Text(constellation.name).font(.title3.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section {
                if constellation.centerJ2000 != nil {
                    HStack {
                        Label(isAboveHorizon ? "Up now" : "Below horizon",
                              systemImage: isAboveHorizon ? "eye" : "eye.slash")
                            .foregroundStyle(isAboveHorizon ? .green : .secondary)
                        Spacer()
                        Text("\(altStr) · \(compassStr)")
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
        .task(id: positionKey) {
            guard let center = constellation.centerJ2000 else { return }
            let jd = appState.skyJulianDate
            let obs = appState.observer
            let h = CoordinateTransforms.horizontal(
                of: CoordinateTransforms.precessFromJ2000(center, julianDate: jd),
                julianDate: jd, observer: obs)
            isAboveHorizon = h.isAboveHorizon
            altStr = AstroFormat.degrees(h.altitude)
            compassStr = h.compassDirection
        }
    }
}
