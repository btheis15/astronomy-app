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
                    Toggle("Milky Way", isOn: $appState.showMilkyWay)
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
                    Picker("Sky darkness", selection: $appState.bortleClass) {
                        ForEach(1...9, id: \.self) { bortle in
                            Text("Bortle \(bortle)").tag(bortle)
                        }
                    }
                    LabeledContent("Limiting magnitude",
                                   value: String(format: "%.1f", appState.bortleLimitingMagnitude))
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                Section {
                    Toggle("Ecliptic", isOn: $appState.showEcliptic)
                    Toggle("Celestial equator", isOn: $appState.showCelestialEquator)
                    Toggle("RA/Dec grid", isOn: $appState.showCoordinateGrid)
                    Toggle("Meteor shower radiants", isOn: $appState.showMeteorShowers)
                } header: {
                    Text("Reference lines")
                } footer: {
                    Text("Great-circle overlays: the ecliptic (the Sun and planets' path), the celestial equator, and a right-ascension/declination grid.")
                }

                Section {
                    Toggle("Satellites", isOn: $appState.showSatellites)
                    Toggle("Starlink constellation", isOn: $appState.showStarlink)
                        .disabled(!appState.showSatellites)
                    Toggle("Notify me before passes", isOn: passNotificationBinding)
                } header: {
                    Text("Satellites")
                } footer: {
                    Text("Shows the ISS, Hubble and other naked-eye satellites. The Starlink option adds up to 300 Starlink satellites from live Celestrak data. Star a satellite in the Catalog to get a heads-up 10 minutes before its visible passes.")
                }

                Section {
                    Toggle("Night vision mode", isOn: $appState.nightMode)
                } footer: {
                    Text("Tints the whole interface red to protect your dark adaptation.")
                }

                Section {
                    NavigationLink {
                        EquipmentEditorView()
                    } label: {
                        Label("Telescope & eyepieces", systemImage: "eyeglasses")
                    }
                    if let scope = appState.equipment.activeTelescope,
                       let eyepiece = appState.equipment.activeEyepiece {
                        LabeledContent("Active",
                                       value: "\(scope.name) + \(eyepiece.name)")
                        LabeledContent("Magnification",
                                       value: "\(Int(scope.focalLengthMM / eyepiece.focalLengthMM))×")
                    }
                } header: {
                    Text("Telescope")
                } footer: {
                    Text("Set up your gear to see what each object looks like through the eyepiece, how hard it is, and how to find it.")
                }

                locationSection

                Section {
                    LabeledContent("Star catalog",
                                   value: appState.catalog.usesDeepCatalog
                                       ? "HYG database (\(appState.catalog.stars.count) stars)"
                                       : "Built-in (\(appState.catalog.stars.count) bright stars)")
                    LabeledContent("Messier objects", value: "110")
                    LabeledContent("Satellites tracked",
                                   value: "\(appState.satelliteService.satellites.count)")
                    LabeledContent("Ephemeris", value: "Meeus / JPL approximations")
                    LabeledContent("Satellite propagator", value: "SGP4 (Vallado)")
                } header: {
                    Text("About")
                } footer: {
                    Text("Star data: Yale Bright Star Catalogue and the HYG database (CC BY-SA 4.0). Deep-sky: Messier, Caldwell & NGC. Ephemerides: Meeus / JPL. Satellite elements: Celestrak. Planet textures: Solar System Scope (CC BY 4.0).")
                }
            }
            .navigationTitle("Settings")
        }
    }

    /// Enabling requests notification authorization, then (re)schedules.
    private var passNotificationBinding: Binding<Bool> {
        Binding(
            get: { appState.passNotificationsEnabled },
            set: { newValue in
                appState.passNotificationsEnabled = newValue
                Task {
                    if newValue { _ = await appState.notificationScheduler.requestAuthorization() }
                    await appState.refreshPassNotifications()
                }
            }
        )
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
