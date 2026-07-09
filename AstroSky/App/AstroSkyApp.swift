//
//  AstroSkyApp.swift
//  AstroSky
//

import SwiftUI

@main
struct AstroSkyApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .preferredColorScheme(.dark)
                .task { appState.start() }
        }
    }
}
