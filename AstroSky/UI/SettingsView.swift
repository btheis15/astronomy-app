//
//  SettingsView.swift
//  AstroSky
//

import CoreLocation
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var manualLatitude = ""
    @State private var manualLongitude = ""

    var body: some View {
        @Bindable var appState = appState
        NavigationStack {
            Form {
                Section("Sky display") {
                    Toggle("Constellation figures", isOn: $appState.showConstellationLines)
                    Toggle("Labels", isOn: $appState.showLabels)
                    Toggle("Deep-sky objects (Messier)", isOn: $appState.showDeepSky)
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Faintest stars")
                            Spacer()
                            Text("mag \(appState.magnitudeLimit, specifier: "%.1f")")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $appState.magnitudeLimit, in: 2.0...6.5, step: 0.5)
                    }
                }

                Section {
                    Toggle("Satellites", isOn: $appState.showSatellites)
                    Toggle("Starlink constellation", isOn: $appState.showStarlink)
                        .disabled(!appState.showSatellites)
                } header: {
                    Text("Satellites")
                } footer: {
                    Text("Shows the ISS, Hubble and other naked-eye satellites. The Starlink option adds up to 300 Starlink satellites from live Celestrak data.")
                }

                Section {
                    Toggle("Night vision mode", isOn: $appState.nightMode)
                } footer: {
                    Text("Tints the whole interface red to protect your dark adaptation.")
                }

                locationSection

                Section("About") {
                    LabeledContent("Star catalog",
                                   value: appState.catalog.usesDeepCatalog
                                       ? "HYG database (\(appState.catalog.stars.count) stars)"
                                       : "Built-in (\(appState.catalog.stars.count) bright stars)")
                    LabeledContent("Messier objects", value: "110")
                    LabeledContent("Satellites tracked",
                                   value: "\(appState.satelliteService.satellites.count)")
                    LabeledContent("Ephemeris", value: "Meeus / JPL approximations")
                    LabeledContent("Satellite propagator", value: "SGP4 (Vallado)")
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var locationSection: some View {
        Section {
            LabeledContent("Current",
                           value: String(format: "%.2f°, %.2f°",
                                         appState.observer.latitudeDegrees,
                                         appState.observer.longitudeDegrees))
            if let place = appState.locationService.placeName {
                LabeledContent("Place", value: place)
            }

            if appState.locationService.manualLocationEnabled {
                Button("Use device location") {
                    appState.locationService.useAutomaticLocation()
                }
            } else if appState.locationService.authorizationStatus == .denied {
                Text("Location access denied — enter coordinates below or enable access in Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack {
                TextField("Latitude", text: $manualLatitude)
                    .keyboardType(.numbersAndPunctuation)
                TextField("Longitude", text: $manualLongitude)
                    .keyboardType(.numbersAndPunctuation)
                Button("Set") {
                    if let lat = Double(manualLatitude), let lon = Double(manualLongitude),
                       abs(lat) <= 90, abs(lon) <= 180 {
                        appState.locationService.setManualLocation(latitudeDegrees: lat,
                                                                   longitudeDegrees: lon)
                    }
                }
                .disabled(Double(manualLatitude) == nil || Double(manualLongitude) == nil)
            }
            .font(.subheadline)
        } header: {
            Text("Location")
        } footer: {
            Text("Astronomy only needs your rough position — a city-level fix is plenty.")
        }
    }
}
