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
import UniformTypeIdentifiers

struct ObservationLogView: View {
    @Query(sort: \ObservationLogEntry.date, order: .reverse) private var entries: [ObservationLogEntry]
    @Environment(\.modelContext) private var context
    @State private var editingEntry: ObservationLogEntry?

    private var messierSeen: Int {
        Set(entries.filter(\.isMessier).map(\.objectID)).count
    }

    private var csvFile: ObservingLogCSV {
        var lines = ["Date,Object,Seeing (1-5),Notes"]
        for entry in entries {
            let dateStr = entry.date.formatted(date: .abbreviated, time: .shortened)
            let notes = entry.notes.replacingOccurrences(of: "\"", with: "\"\"")
            lines.append("\"\(dateStr)\",\"\(entry.objectName)\",\(entry.seeingRating),\"\(notes)\"")
        }
        let datestamp = Date().formatted(.iso8601.year().month().day())
        return ObservingLogCSV(content: lines.joined(separator: "\n"),
                               filename: "AstroSky-log-\(datestamp).csv")
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
                                           description: Text("Tap \"Log observation\" on any object to start your log."))
                }
            } else {
                Section("Entries") {
                    ForEach(entries) { entry in
                        Button { editingEntry = entry } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(entry.objectName).font(.headline).foregroundStyle(.primary)
                                    Spacer()
                                    if entry.seeingRating > 0 {
                                        Text(String(repeating: "★", count: entry.seeingRating))
                                            .foregroundStyle(.yellow).font(.caption)
                                    }
                                }
                                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                                if !entry.notes.isEmpty {
                                    Text(entry.notes).font(.subheadline).foregroundStyle(.primary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { indexSet in
                        for index in indexSet { context.delete(entries[index]) }
                    }
                }
            }
        }
        .navigationTitle("Observing Log")
        .toolbar {
            if !entries.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ShareLink(
                        item: csvFile,
                        preview: SharePreview("Observing Log", image: Image(systemName: "list.star"))
                    )
                }
            }
        }
        .sheet(item: $editingEntry) { entry in
            EditObservationSheet(entry: entry)
        }
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

// MARK: - Edit an existing observation

struct EditObservationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var entry: ObservationLogEntry

    var body: some View {
        NavigationStack {
            Form {
                Section("Object") {
                    LabeledContent("Name", value: entry.objectName)
                    LabeledContent("Date", value: entry.date.formatted(date: .abbreviated, time: .shortened))
                }
                Section("Seeing") {
                    HStack(spacing: 8) {
                        ForEach(1...5, id: \.self) { value in
                            Image(systemName: value <= entry.seeingRating ? "star.fill" : "star")
                                .font(.title3)
                                .foregroundStyle(value <= entry.seeingRating ? .yellow : .secondary)
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                                .onTapGesture { entry.seeingRating = value }
                                .accessibilityLabel("\(value) star\(value == 1 ? "" : "s")")
                                .accessibilityAddTraits(value == entry.seeingRating ? .isSelected : [])
                        }
                    }
                }
                Section("Notes") {
                    TextField("Notes", text: $entry.notes, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle("Edit Observation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
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
                    HStack(spacing: 8) {
                        ForEach(1...5, id: \.self) { value in
                            Image(systemName: value <= seeing ? "star.fill" : "star")
                                .font(.title3)
                                .foregroundStyle(value <= seeing ? .yellow : .secondary)
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                                .onTapGesture { seeing = value }
                                .accessibilityLabel("\(value) star\(value == 1 ? "" : "s")")
                                .accessibilityAddTraits(value == seeing ? .isSelected : [])
                        }
                    }
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

// MARK: - CSV export

/// A named .csv file that recipients receive as an attachment rather than
/// pasted text. Conforms to Transferable via FileRepresentation.
struct ObservingLogCSV: Transferable {
    let content: String
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { csv in
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(csv.filename)
            try csv.content.write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}
