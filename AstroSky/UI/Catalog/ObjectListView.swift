//
//  ObjectListView.swift
//  AstroSky
//

import SwiftUI

struct ObjectListView: View {
    @Environment(AppState.self) private var appState
    let title: String
    let objects: [any CelestialObject]
    @State private var query = ""
    @State private var visibleOnly = false
    /// Altitude cache (degrees) computed when visibleOnly is toggled on.
    @State private var altitudes: [String: Double] = [:]

    private var queryFiltered: [any CelestialObject] {
        guard !query.isEmpty else { return objects }
        return objects.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.subtitle.localizedCaseInsensitiveContains(query)
        }
    }

    private var displayed: [any CelestialObject] {
        guard visibleOnly, !altitudes.isEmpty else { return queryFiltered }
        return queryFiltered
            .filter { (altitudes[$0.id] ?? -90) >= 10 }
            .sorted { (altitudes[$0.id] ?? -90) > (altitudes[$1.id] ?? -90) }
    }

    var body: some View {
        List(displayed, id: \.id) { object in
            NavigationLink {
                ObjectDetailView(object: object)
            } label: {
                CatalogRow(object: object)
            }
        }
        .navigationTitle(title)
        .searchable(text: $query)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    visibleOnly.toggle()
                } label: {
                    Image(systemName: visibleOnly ? "eye.fill" : "eye")
                        .foregroundStyle(visibleOnly ? .indigo : .primary)
                }
                .accessibilityLabel(visibleOnly ? "Show all objects" : "Show visible objects only")
            }
        }
        .overlay {
            if objects.isEmpty {
                ContentUnavailableView("Nothing here yet",
                                       systemImage: "antenna.radiowaves.left.and.right.slash",
                                       description: Text("Satellite data loads from Celestrak when online."))
            } else if displayed.isEmpty && visibleOnly {
                ContentUnavailableView("Nothing above 10° right now",
                                       systemImage: "eye.slash",
                                       description: Text("Try again later or turn off the visibility filter."))
            }
        }
        // Compute altitudes off the main actor whenever the filter is enabled.
        .task(id: visibleOnly) {
            guard visibleOnly else { return }
            let jd = appState.skyJulianDate
            let obs = appState.observer
            let objs = objects
            altitudes = await Task.detached(priority: .utility) {
                Dictionary(objs.map { ($0.id, $0.horizontal(julianDate: jd, observer: obs).altitudeDegrees) },
                           uniquingKeysWith: { first, _ in first })
            }.value
        }
    }
}
