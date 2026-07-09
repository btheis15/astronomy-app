//
//  LogView.swift
//  AstroSky
//
//  The observing log: a persisted list of what you've seen, a Messier "seen"
//  progress ring, and a sheet to log a new observation pre-filled with the
//  current sky conditions.
//

import SwiftData
import SwiftUI

struct ObservationLogView: View {
    @Query(sort: \ObservationLogEntry.date, order: .reverse) private var entries: [ObservationLogEntry]
    @Environment(\.modelContext) private var context

    private var messierSeen: Int {
        Set(entries.filter(\.isMessier).map(\.objectID)).count
    }

    var body: some View {
        List {
            Section {
                MessierProgressRing(seen: messierSeen, total: 110)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }

            if entries.isEmpty {
                Section {
                    ContentUnavailableView("No observations yet",
                                           systemImage: "book.closed",
                                           description: Text("Tap “Log observation” on any object to start your log."))
                }
            } else {
                Section("Entries") {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.objectName).font(.headline)
                                Spacer()
                                if entry.seeingRating > 0 {
                                    Text(String(repeating: "★", count: entry.seeingRating))
                                        .foregroundStyle(.yellow).font(.caption)
                                }
                            }
                            Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                            if !entry.notes.isEmpty {
                                Text(entry.notes).font(.subheadline)
                            }
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet { context.delete(entries[index]) }
                    }
                }
            }
        }
        .navigationTitle("Observing Log")
    }
}

struct MessierProgressRing: View {
    let seen: Int
    let total: Int

    private var fraction: Double { total > 0 ? Double(seen) / Double(total) : 0 }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(.indigo, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(seen)").font(.title.bold().monospacedDigit())
                    Text("of \(total)").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 120, height: 120)
            Text("Messier objects seen").font(.subheadline).foregroundStyle(.secondary)
        }
        .accessibilityLabel("\(seen) of \(total) Messier objects seen")
    }
}

// MARK: - Log a new observation

struct LogObservationSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let object: any CelestialObject

    @State private var notes = ""
    @State private var seeing = 3

    var body: some View {
        NavigationStack {
            Form {
                Section("Conditions") {
                    LabeledContent("Object", value: object.name)
                    LabeledContent("When", value: Date().formatted(date: .abbreviated, time: .shortened))
                    let horizontal = object.horizontal(julianDate: appState.skyJulianDate,
                                                       observer: appState.observer)
                    LabeledContent("Altitude", value: AstroFormat.degrees(horizontal.altitude))
                    LabeledContent("Moon", value: MoonEphemeris.phase(julianDate: appState.skyJulianDate).phaseName)
                }
                Section("Seeing") {
                    Picker("Rating", selection: $seeing) {
                        ForEach(1...5, id: \.self) { Text(String(repeating: "★", count: $0)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Notes") {
                    TextField("What did you see?", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Log Observation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
    }

    private func save() {
        let isMessier = (object as? DeepSkyObject)?.catalog == .messier
        let entry = ObservationLogEntry(objectID: object.id,
                                        objectName: object.name,
                                        notes: notes,
                                        seeingRating: seeing,
                                        latitude: appState.observer.latitudeDegrees,
                                        longitude: appState.observer.longitudeDegrees,
                                        isMessier: isMessier)
        context.insert(entry)
        dismiss()
    }
}
