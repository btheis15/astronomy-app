//
//  ObjectDetailView.swift
//  AstroSky
//
//  Full object page: live position, physical data, rise/transit/set and an
//  altitude-over-tonight chart.
//

import Charts
import SwiftUI

struct ObjectDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let object: any CelestialObject
    @State private var showLogSheet = false
    @ScaledMetric private var headerIconSize: CGFloat = 46

    var body: some View {
        List {
            photoHeroSection
            headerSection
            positionSection
            riseSetSection
            AltitudeChartSection(object: object)
            infoSection
            if object.kind != .satellite {
                TelescopeSection(object: object)
                Section {
                    Button {
                        showLogSheet = true
                    } label: {
                        Label("Log observation", systemImage: "book.and.wrench")
                    }
                }
            }
        }
        .navigationTitle(object.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    appState.toggleFavorite(object.id)
                } label: {
                    Image(systemName: appState.isFavorite(object.id) ? "star.fill" : "star")
                        .foregroundStyle(appState.isFavorite(object.id) ? .yellow : .secondary)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appState.select(object)
                    appState.guideTargetID = object.id
                    appState.skyTabRequested = true
                    dismiss()
                } label: {
                    Label("Find in AR", systemImage: "arkit")
                }
            }
        }
        .sheet(isPresented: $showLogSheet) {
            LogObservationSheet(object: object)
        }
    }

    @ViewBuilder private var photoHeroSection: some View {
        if ObjectImagery.hasImage(for: object) {
            Section {
                ObjectPhotoGallery(object: object, height: 240)
                    .listRowInsets(EdgeInsets())
            } footer: {
                Text(ObjectImagery.attribution)
            }
        }
    }

    private var headerSection: some View {
        Section {
            HStack(spacing: 14) {
                ObjectGlyph(object: object, size: headerIconSize)
                VStack(alignment: .leading, spacing: 3) {
                    Text(object.name).font(.title3.weight(.semibold))
                    Text(object.subtitle).font(.subheadline).foregroundStyle(.secondary)
                    Text(object.kind.rawValue)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }
            }
        }
    }

    private var positionSection: some View {
        let position = object.skyPosition(julianDate: appState.skyJulianDate,
                                          observer: appState.observer)
        return Section("Position now") {
            row("Altitude", AstroFormat.degrees(position.horizontal.altitude))
            row("Azimuth", AstroFormat.azimuth(position.horizontal))
            row("Right ascension", AstroFormat.rightAscension(position.equatorialJ2000))
            row("Declination", AstroFormat.declination(position.equatorialJ2000))
            if let distance = position.distanceDescription {
                row("Distance", distance)
            }
            row("Visibility", position.horizontal.isAboveHorizon
                ? "Above the horizon" : "Below the horizon")
        }
    }

    private var riseSetSection: some View {
        // Satellites move too fast for daily rise/set to be meaningful.
        Group {
            if object.kind != .satellite {
                let dayStart = Calendar.current.startOfDay(for: appState.skyDate)
                let observer = appState.observer
                let events = RiseSetCalculator.events(startingAt: dayStart,
                                                      threshold: threshold) { date in
                    let jd = AstroTime.julianDate(date)
                    return object.horizontal(julianDate: jd, observer: observer).altitude
                }
                Section("Today") {
                    if events.alwaysUp {
                        row("Visibility", "Circumpolar — up all day")
                    } else if events.alwaysDown {
                        row("Visibility", "Never rises today")
                    } else {
                        row("Rise", AstroFormat.time(events.rise))
                        row("Set", AstroFormat.time(events.set))
                    }
                    row("Transit", AstroFormat.time(events.transit))
                    if let transitAltitude = events.transitAltitude {
                        row("Max altitude", AstroFormat.degrees(transitAltitude))
                    }
                }
            }
        }
    }

    private var threshold: Double {
        switch object.kind {
        case .sun: RiseSetCalculator.Threshold.sun
        case .moon: RiseSetCalculator.Threshold.moon
        default: RiseSetCalculator.Threshold.star
        }
    }

    private var infoSection: some View {
        Section("Details") {
            let rows = object.infoRows(julianDate: appState.skyJulianDate,
                                       observer: appState.observer)
            ForEach(rows.indices, id: \.self) { index in
                row(rows[index].label, rows[index].value)
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.subheadline)
    }
}

// MARK: - Altitude chart

struct AltitudeChartSection: View {
    @Environment(AppState.self) private var appState
    let object: any CelestialObject

    private struct Sample: Identifiable {
        let date: Date
        let altitudeDegrees: Double
        var id: Date { date }
    }

    /// Cached curve — recomputed only when the object or the day changes, not
    /// on every body evaluation (each sample is a full ephemeris solve).
    @State private var samples: [Sample] = []

    private var reloadKey: String {
        let day = Int(Calendar.current.startOfDay(for: appState.skyDate).timeIntervalSince1970)
        return "\(object.id)|\(day)|\(Int(appState.observer.latitude * 100))|\(Int(appState.observer.longitude * 100))"
    }

    private static func computeSamples(object: any CelestialObject, date: Date, observer: Observer) -> [Sample] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        guard let noon = calendar.date(byAdding: .hour, value: 12, to: dayStart) else { return [] }
        return stride(from: 0.0, through: 24.0, by: 0.25).map { hours in
            let sampleDate = noon.addingTimeInterval(hours * 3600)
            let jd = AstroTime.julianDate(sampleDate)
            let altitude = object.horizontal(julianDate: jd, observer: observer).altitudeDegrees
            return Sample(date: sampleDate, altitudeDegrees: altitude)
        }
    }

    var body: some View {
        // A chart is meaningless for satellites (many orbits per day).
        if object.kind != .satellite {
            Section("Altitude · noon to noon") {
                Chart(samples) { sample in
                    LineMark(x: .value("Time", sample.date),
                             y: .value("Altitude", sample.altitudeDegrees))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.indigo)

                    AreaMark(x: .value("Time", sample.date),
                             yStart: .value("Horizon", 0),
                             yEnd: .value("Altitude", max(0, sample.altitudeDegrees)))
                    .foregroundStyle(.indigo.opacity(0.15))
                }
                .chartYScale(domain: -90...90)
                .chartYAxis {
                    AxisMarks(values: [-90, -45, 0, 45, 90]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Int.self) { Text("\(v)°") }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour())
                    }
                }
                .frame(height: 180)
                .padding(.vertical, 4)

                if let now = samples.min(by: {
                    abs($0.date.timeIntervalSince(appState.skyDate)) < abs($1.date.timeIntervalSince(appState.skyDate))
                }) {
                    HStack {
                        Text("Now").foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%+.1f°", now.altitudeDegrees)).monospacedDigit()
                    }
                    .font(.subheadline)
                }
            }
            .task(id: reloadKey) {
                samples = Self.computeSamples(object: object, date: appState.skyDate, observer: appState.observer)
            }
        }
    }
}
