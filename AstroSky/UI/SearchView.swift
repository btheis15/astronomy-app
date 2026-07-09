//
//  SearchView.swift
//  AstroSky
//

import SwiftUI

struct SearchView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var results: [any CelestialObject] {
        appState.search(query)
    }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    Section("Suggestions") {
                        suggestionRow(appState.catalog.moon)
                        ForEach(appState.catalog.planets.prefix(4), id: \.id) { planet in
                            suggestionRow(planet)
                        }
                        if let iss = appState.satelliteService.featured.first(where: \.isISS) {
                            suggestionRow(iss)
                        }
                        if let m31 = MessierCatalog.objectsByNumber[31] {
                            suggestionRow(m31)
                        }
                    }
                } else {
                    ForEach(results, id: \.id) { object in
                        resultRow(object)
                    }
                }
            }
            .navigationTitle("Search the sky")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Stars, planets, M31, ISS, Starlink…")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func suggestionRow(_ object: any CelestialObject) -> some View {
        resultRow(object)
    }

    private func resultRow(_ object: any CelestialObject) -> some View {
        let horizontal = object.horizontal(julianDate: appState.skyJulianDate,
                                           observer: appState.observer)
        return Button {
            appState.select(object)
            appState.guideTargetID = object.id
            appState.skyTabRequested = true
            dismiss()
        } label: {
            HStack {
                ObjectGlyph(object: object, size: 30)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(object.name).foregroundStyle(.primary)
                    Text(object.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(horizontal.isAboveHorizon ? "Up" : "Below horizon")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(horizontal.isAboveHorizon ? .green : .secondary)
                    Text(AstroFormat.degrees(horizontal.altitude))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
