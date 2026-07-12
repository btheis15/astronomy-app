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

    // MARK: - Cached expensive computations

    /// Cached sky position — recomputed only every ~5 s of real time.
    @State private var cachedPosition: SkyPosition? = nil

    /// Cached rise/set events — recomputed only when the day changes.
    @State private var cachedRiseSet: RiseSetEvents? = nil

    /// Cached info rows — recomputed only every ~5 s of real time.
    @State private var cachedInfoRows: [(label: String, value: String)] = []

    /// 17280 = 86400 s/day ÷ 5 s/tick: changes roughly every 5 s of sky time.
    private static let jdTicksPerDay: Double = 17_280
    private var positionKey: Int { Int(appState.skyJulianDate * Self.jdTicksPerDay) }

    /// Changes when the calendar day (or observer location) changes.
    private var dayKey: String {
        let day = Int(Calendar.current.startOfDay(for: appState.skyDate).timeIntervalSince1970)
        return "\(object.id)|\(day)|\(Int(appState.observer.latitude * 100))|\(Int(appState.observer.longitude * 100))"
    }

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
                    appState.favorites.toggle(object.id)
                } label: {
                    Image(systemName: appState.favorites.isFavorite(object.id) ? "star.fill" : "star")
                        .foregroundStyle(appState.favorites.isFavorite(object.id) ? .yellow : .secondary)
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
        // Recompute position and info rows every ~5 s of sky time.
        .task(id: positionKey) {
            let jd = appState.skyJulianDate
            let observer = appState.observer
            cachedPosition = object.skyPosition(julianDate: jd, observer: observer)
            cachedInfoRows = object.infoRows(julianDate: jd, observer: observer)
        }
        // Recompute rise/set once per day (expensive bisection search).
        .task(id: dayKey) {
            guard object.kind != .satellite else {
                cachedRiseSet = nil
                return
            }
            let dayStart = Calendar.current.startOfDay(for: appState.skyDate)
            let observer = appState.observer
            let thresh = threshold
            let obj = object
            cachedRiseSet = await Task.detached(priority: .userInitiated) {
                RiseSetCalculator.events(startingAt: dayStart, threshold: thresh) { date in
                    let jd = AstroTime.julianDate(date)
                    return obj.horizontal(julianDate: jd, observer: observer).altitude
                }
            }.value
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
        Section("Position now") {
            if let position = cachedPosition {
                DetailRow(label: "Altitude", value: AstroFormat.degrees(position.horizontal.altitude))
                DetailRow(label: "Azimuth", value: AstroFormat.azimuth(position.horizontal))
                DetailRow(label: "Right ascension", value: AstroFormat.rightAscension(position.equatorialJ2000))
                DetailRow(label: "Declination", value: AstroFormat.declination(position.equatorialJ2000))
                if let distance = position.distanceDescription {
                    DetailRow(label: "Distance", value: distance)
                }
                DetailRow(label: "Visibility", value: position.horizontal.isAboveHorizon
                    ? "Above the horizon" : "Below the horizon")
            } else {
                DetailRow(label: "Altitude", value: "—")
                DetailRow(label: "Azimuth", value: "—")
                DetailRow(label: "Right ascension", value: "—")
                DetailRow(label: "Declination", value: "—")
            }
        }
    }

    private var riseSetSection: some View {
        // Satellites move too fast for daily rise/set to be meaningful.
        Group {
            if object.kind != .satellite {
                Section("Today") {
                    if let events = cachedRiseSet {
                        if events.alwaysUp {
                            DetailRow(label: "Visibility", value: "Circumpolar — up all day")
                        } else if events.alwaysDown {
                            DetailRow(label: "Visibility", value: "Never rises today")
                        } else {
                            DetailRow(label: "Rise", value: AstroFormat.time(events.rise))
                            DetailRow(label: "Set", value: AstroFormat.time(events.set))
                        }
                        DetailRow(label: "Transit", value: AstroFormat.time(events.transit))
                        if let transitAltitude = events.transitAltitude {
                            DetailRow(label: "Max altitude", value: AstroFormat.degrees(transitAltitude))
                        }
                    } else {
                        ProgressView()
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
            ForEach(cachedInfoRows.indices, id: \.self) { index in
                DetailRow(label: cachedInfoRows[index].label, value: cachedInfoRows[index].value)
            }
        }
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
