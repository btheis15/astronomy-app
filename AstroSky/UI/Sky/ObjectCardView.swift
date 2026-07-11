//
//  ObjectCardView.swift
//  AstroSky
//

import SwiftUI

struct ObjectCardView: View {
    @Environment(AppState.self) private var appState
    let object: any CelestialObject
    @State private var showDetail = false
    @State private var altStr = "—"
    @State private var azStr = "—"

    private let positionTicksPerDay: Int = 17280

    /// Changes every 5 real seconds — limits how often we rerun ephemeris.
    private var positionKey: Int { Int(appState.skyJulianDate * Double(positionTicksPerDay)) }

    var body: some View {
        HStack(spacing: 12) {
            ObjectGlyph(object: object, size: 38)
                .frame(width: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(object.name).font(.headline)
                Text(object.subtitle).font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Label(altStr, systemImage: "arrow.up.and.down")
                    Label(azStr, systemImage: "safari")
                    if let magnitude = object.magnitude {
                        Label(AstroFormat.magnitude(magnitude), systemImage: "sun.max")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(spacing: 8) {
                Button {
                    showDetail = true
                } label: {
                    Image(systemName: "info.circle").font(.title3)
                }
                Button {
                    appState.select(nil)
                } label: {
                    Image(systemName: "xmark.circle").font(.title3)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .sheet(isPresented: $showDetail) {
            NavigationStack {
                ObjectDetailView(object: object)
            }
        }
        .task(id: positionKey) {
            let pos = object.skyPosition(julianDate: appState.skyJulianDate,
                                         observer: appState.observer)
            altStr = AstroFormat.degrees(pos.horizontal.altitude)
            azStr = AstroFormat.azimuth(pos.horizontal)
        }
    }
}
