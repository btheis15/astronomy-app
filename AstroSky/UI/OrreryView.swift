//
//  OrreryView.swift
//  AstroSky
//
//  A Sun-centered 3D orrery: a non-AR RealityKit scene showing the planets on
//  their orbits with log-scaled distances, a date scrubber sharing the app's
//  time-travel offset, and drag/pinch camera control.
//

import RealityKit
import SwiftUI

struct OrreryView: View {
    @Environment(AppState.self) private var appState
    /// Bumped once after the view is on screen to force RealityKit to draw its
    /// first frame — a `.nonAR` ARView otherwise stays black until interacted with.
    @State private var renderTick = 0

    var body: some View {
        @Bindable var appState = appState
        ZStack(alignment: .bottom) {
            OrrerySceneView(julianDate: appState.skyJulianDate, renderTick: renderTick)
                .ignoresSafeArea()
                .task { renderTick += 1 }

            VStack(spacing: 8) {
                if !appState.isLiveTime {
                    Text(appState.skyDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.footnote.monospacedDigit().weight(.medium))
                }
                HStack {
                    Text("−1y").font(.caption2)
                    Slider(value: $appState.timeOffset, in: -365 * 86_400...365 * 86_400, step: 86_400)
                    Text("+1y").font(.caption2)
                }
                Button("Today") { appState.resetToLiveTime() }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding()
        }
        .navigationTitle("Orrery")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct OrrerySceneView: UIViewRepresentable {
    let julianDate: Double
    /// Change-only trigger: a new value forces `updateUIView`, which reassigns
    /// entity transforms and thereby dirties the scene so it renders.
    let renderTick: Int

    func makeCoordinator() -> OrreryScene { OrreryScene() }

    func makeUIView(context: Context) -> ARView {
        context.coordinator.makeView()
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.update(julianDate: julianDate)
    }
}
