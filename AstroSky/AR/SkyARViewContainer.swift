//
//  SkyARViewContainer.swift
//  AstroSky
//
//  SwiftUI wrapper for the RealityKit sky view.
//

import RealityKit
import SwiftUI

struct SkyARViewContainer: UIViewRepresentable {
    let appState: AppState
    /// Force the drag-to-look mode even when AR is available.
    var preferManualMode: Bool
    var onGuideUpdate: (GuideReadout?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(appState: appState, preferManualMode: preferManualMode)
    }

    func makeUIView(context: Context) -> ARView {
        let renderer = context.coordinator.renderer
        renderer.onGuideUpdate = onGuideUpdate
        return renderer.arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.renderer.onGuideUpdate = onGuideUpdate
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        coordinator.renderer.tearDown()
    }

    @MainActor
    final class Coordinator {
        let renderer: SkyRenderer

        init(appState: AppState, preferManualMode: Bool) {
            renderer = SkyRenderer(appState: appState, preferManualMode: preferManualMode)
        }
    }
}
