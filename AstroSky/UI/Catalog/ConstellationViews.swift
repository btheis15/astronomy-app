//
//  ConstellationViews.swift
//  AstroSky
//

import SwiftUI

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
