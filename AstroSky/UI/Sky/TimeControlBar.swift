//
//  TimeControlBar.swift
//  AstroSky
//

import SwiftUI

struct TimeControlBar: View {
    @Environment(AppState.self) private var appState
    @Binding var isExpanded: Bool
    @State private var showDatePicker = false

    private let halfDaySeconds: TimeInterval = 43_200
    private let oneDaySeconds: TimeInterval = 86_400
    private let fiveMinuteStep: TimeInterval = 300

    var body: some View {
        @Bindable var appState = appState
        VStack(spacing: 8) {
            HStack {
                // Tapping the date/time text opens a full DatePicker sheet.
                Button {
                    showDatePicker = true
                } label: {
                    Text(appState.skyDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.footnote.monospacedDigit().weight(.medium))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                Spacer()
                Button {
                    appState.resetToLiveTime()
                    isExpanded = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
            }

            Slider(value: $appState.timeOffset, in: -halfDaySeconds...halfDaySeconds, step: fiveMinuteStep) {
                Text("Time offset")
            } minimumValueLabel: {
                Text("−12h").font(.caption2)
            } maximumValueLabel: {
                Text("+12h").font(.caption2)
            }

            HStack(spacing: 10) {
                timeJumpButton("−1d", seconds: -oneDaySeconds)
                timeJumpButton("−1h", seconds: -3600)
                timeJumpButton("+1h", seconds: 3600)
                timeJumpButton("+1d", seconds: oneDaySeconds)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .sheet(isPresented: $showDatePicker) {
            DatePickerSheet()
                .nightModeAware()
        }
    }

    /// Jump buttons are clamped to the slider range so the slider and the
    /// displayed date stay in sync — pressing "+1d" three times no longer
    /// silently advances the sky past the +12 h slider maximum.
    private func timeJumpButton(_ label: String, seconds: TimeInterval) -> some View {
        Button(label) {
            appState.timeOffset = max(-halfDaySeconds, min(halfDaySeconds, appState.timeOffset + seconds))
        }
        .font(.caption.weight(.semibold))
        .buttonStyle(.bordered)
    }
}

// MARK: - Date picker sheet

private struct DatePickerSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DatePicker(
                "Sky date and time",
                selection: Binding(
                    get: { appState.skyDate },
                    set: { appState.timeOffset = $0.timeIntervalSinceNow }
                ),
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.graphical)
            .padding()
            .navigationTitle("Travel to date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Now") {
                        appState.resetToLiveTime()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
