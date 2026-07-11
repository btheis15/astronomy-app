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
