//
//  AstroSkyApp.swift
//  AstroSky
//

import SwiftUI

@main
struct AstroSkyApp: App {
    @State private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .preferredColorScheme(.dark)
                .task { appState.start() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await appState.refreshPassNotifications() }
                    }
                }
        }
    }
}
