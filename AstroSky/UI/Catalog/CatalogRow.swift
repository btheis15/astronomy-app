//
//  CatalogRow.swift
//  AstroSky
//

import SwiftUI

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
                    Image(systemName: appState.favorites.isFavoriteSatellite(object.id) ? "star.fill" : "star")
                        .foregroundStyle(appState.favorites.isFavoriteSatellite(object.id) ? .yellow : .secondary)
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
