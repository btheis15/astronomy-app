//
//  EventDetailView.swift
//  AstroSky
//
//  Detail view for sky events: meteor showers (ZHR, radiant, moon interference),
//  conjunctions (both bodies, separation, altitudes), and moon phases/eclipses.
//

import SwiftUI

struct EventDetailView: View {
    @Environment(AppState.self) private var appState
    let event: AstroEvent

    private var eventJD: Double { AstroTime.julianDate(event.date) }

    var body: some View {
        List {
            headerSection
            switch event.kind {
            case .meteorShower:
                if let shower = matchedShower { meteorSection(shower) }
            case .conjunction:
                conjunctionSection
            default:
                moonEventSection
            }
        }
        .navigationTitle(event.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var headerSection: some View {
        Section {
            LabeledContent("Date",
                           value: event.date.formatted(date: .complete, time: .omitted))
            LabeledContent("Time",
                           value: event.date.formatted(date: .omitted, time: .shortened))
            HStack(alignment: .top) {
                Image(systemName: event.kind.iconSystemName)
                    .foregroundStyle(.yellow)
                    .frame(width: 20)
                Text(event.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Meteor shower

    private var matchedShower: MeteorShower? {
        // Event title is "{ShowerName} peak", e.g. "Perseids peak"
        let name = event.title.replacingOccurrences(of: " peak", with: "")
        return MeteorShowers.all.first { $0.name == name }
    }

    @ViewBuilder
    private func meteorSection(_ shower: MeteorShower) -> some View {
        Section("Shower details") {
            LabeledContent("Peak ZHR", value: "~\(shower.zhr) meteors/hour")
            LabeledContent("Radiant RA",
                           value: String(format: "%.1f°", shower.radiantRAHours * 15))
            LabeledContent("Radiant Dec",
                           value: AstroFormat.degrees(shower.radiantDecDegrees * AstroMath.degToRad))
            LabeledContent("Active window",
                           value: "±\(shower.activeWindowDays) days from peak")
        }

        Section("At your location") {
            let horiz = CoordinateTransforms.horizontal(of: shower.radiant,
                                                        julianDate: eventJD,
                                                        observer: appState.observer)
            LabeledContent("Radiant altitude at peak",
                           value: horiz.isAboveHorizon
                               ? AstroFormat.degrees(horiz.altitude)
                               : "Below horizon")
            let phase = MoonEphemeris.phase(julianDate: eventJD)
            LabeledContent("Moon at peak",
                           value: "\(Int((phase.illuminatedFraction * 100).rounded()))% · \(phase.phaseName)")
        }

        Section {
            Button {
                appState.showMeteorShowers = true
                appState.skyTabRequested = true
            } label: {
                Label("Find radiant in AR", systemImage: "sparkles")
            }
        } footer: {
            Text("Enables meteor shower radiants on the sky overlay and switches to the Sky view.")
        }
    }

    // MARK: - Conjunction

    @ViewBuilder
    private var conjunctionSection: some View {
        // Title format: "BodyA & BodyB conjunction"
        let parts = event.title
            .replacingOccurrences(of: " conjunction", with: "")
            .components(separatedBy: " & ")
        let nameA = parts.first ?? ""
        let nameB = parts.dropFirst().first ?? ""

        Section("Bodies") {
            bodyRow(name: nameA)
            bodyRow(name: nameB)
        }

        Section("Observing") {
            let altA = bodyAltitude(name: nameA)
            let altB = bodyAltitude(name: nameB)
            if let altA {
                LabeledContent(nameA, value: altA)
            }
            if let altB {
                LabeledContent(nameB, value: altB)
            }
            Text("Both objects will fit in a binocular field of view.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if let obj = catalogObject(name: nameA) ?? catalogObject(name: nameB) {
            Section {
                Button {
                    appState.select(obj)
                    appState.guideTargetID = obj.id
                    appState.skyTabRequested = true
                } label: {
                    Label("Find \(obj.name) in AR", systemImage: "arkit")
                }
            }
        }
    }

    private func bodyRow(name: String) -> some View {
        HStack(spacing: 12) {
            if let obj = catalogObject(name: name) {
                ObjectGlyph(object: obj, size: 28).frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                    Text(obj.subtitle).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "circle.circle").frame(width: 32)
                Text(name)
            }
        }
    }

    private func bodyAltitude(name: String) -> String? {
        guard let obj = catalogObject(name: name) else { return nil }
        let h = obj.horizontal(julianDate: eventJD, observer: appState.observer)
        return h.isAboveHorizon
            ? AstroFormat.degrees(h.altitude) + " · " + h.compassDirection
            : "Below horizon"
    }

    private func catalogObject(name: String) -> (any CelestialObject)? {
        appState.catalog.object(withName: name)
    }

    // MARK: - Moon phase / eclipse

    @ViewBuilder
    private var moonEventSection: some View {
        Section("Moon at event time") {
            let phase = MoonEphemeris.phase(julianDate: eventJD)
            LabeledContent("Phase", value: phase.phaseName)
            LabeledContent("Illuminated",
                           value: "\(Int((phase.illuminatedFraction * 100).rounded()))%")
        }
        Section {
            NavigationLink {
                ObjectDetailView(object: appState.catalog.moon)
            } label: {
                Label("Open Moon detail", systemImage: "moon.fill")
            }
        }
    }
}
