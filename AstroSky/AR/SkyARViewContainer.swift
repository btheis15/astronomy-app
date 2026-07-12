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
    var skyDisplayMode: SkyDisplayMode
    var onGuideUpdate: (GuideReadout?) -> Void
    var onTrackingHint: ((String?) -> Void)?
    /// Hands the live renderer back to SwiftUI (for the shutter button).
    var onRendererReady: (SkyRenderer) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(appState: appState, skyDisplayMode: skyDisplayMode)
    }

    func makeUIView(context: Context) -> ARView {
        let renderer = context.coordinator.renderer
        renderer.onGuideUpdate = onGuideUpdate
        renderer.onTrackingHint = onTrackingHint
        onRendererReady(renderer)
        return renderer.arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.renderer.onGuideUpdate = onGuideUpdate
        context.coordinator.renderer.onTrackingHint = onTrackingHint
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        coordinator.renderer.tearDown()
    }

    @MainActor
    final class Coordinator {
        let renderer: SkyRenderer

        init(appState: AppState, skyDisplayMode: SkyDisplayMode) {
            renderer = SkyRenderer(appState: appState, skyDisplayMode: skyDisplayMode)
        }
    }
}
