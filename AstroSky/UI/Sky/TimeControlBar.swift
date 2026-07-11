//
//  TimeControlBar.swift
//  AstroSky
//

import SwiftUI

struct TimeControlBar: View {
    @Environment(AppState.self) private var appState
    @Binding var isExpanded: Bool

    private let halfDaySeconds: TimeInterval = 43_200
    private let oneDaySeconds: TimeInterval = 86_400
    private let fiveMinuteStep: TimeInterval = 300

    var body: some View {
        @Bindable var appState = appState
        VStack(spacing: 8) {
            HStack {
                Text(appState.skyDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.footnote.monospacedDigit().weight(.medium))
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
    }

    private func timeJumpButton(_ label: String, seconds: TimeInterval) -> some View {
        Button(label) {
            appState.timeOffset += seconds
        }
        .font(.caption.weight(.semibold))
        .buttonStyle(.bordered)
    }
}
