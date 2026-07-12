//
//  RootView.swift
//  AstroSky
//

import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab: Tab = .sky
    @State private var showOnboarding = false

    enum Tab: Hashable {
        case sky, explore, tonight, catalog, settings
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            SkyTabView()
                .tabItem { Label("Sky", systemImage: "sparkles.rectangle.stack") }
                .tag(Tab.sky)

            ExploreTabView()
                .tabItem { Label("Explore", systemImage: "circle.hexagonpath") }
                .tag(Tab.explore)

            TonightView()
                .tabItem { Label("Tonight", systemImage: "moon.stars") }
                .tag(Tab.tonight)

            CatalogView()
                .tabItem { Label("Catalog", systemImage: "list.star") }
                .tag(Tab.catalog)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .tint(appState.nightMode ? .red : .indigo)
        .onChange(of: appState.skyTabRequested) { _, requested in
            if requested {
                selectedTab = .sky
                appState.skyTabRequested = false
            }
        }
        .overlay {
            if appState.nightMode {
                NightModeOverlay()
            }
        }
        .task { showOnboarding = !appState.hasOnboarded }
        .onChange(of: appState.hasOnboarded) { _, isOnboarded in
            if !isOnboarded { showOnboarding = true }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView { showOnboarding = false }
        }
    }
}

/// Red-tint overlay that preserves dark adaptation. Purely visual — it
/// multiplies everything underneath toward red and never intercepts touches.
struct NightModeOverlay: View {
    var body: some View {
        Rectangle()
            .fill(Color.red)
            .opacity(0.45)
            .blendMode(.multiply)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Night-mode sheet helper

/// Applies the red tint and overlay to sheets/covers presented at night.
/// Sheets present above the root overlay, so each one needs its own tint.
private struct NightModeSheetModifier: ViewModifier {
    @Environment(AppState.self) private var appState
    func body(content: Content) -> some View {
        content
            .tint(appState.nightMode ? .red : .indigo)
            .overlay { if appState.nightMode { NightModeOverlay() } }
    }
}

extension View {
    func nightModeAware() -> some View {
        modifier(NightModeSheetModifier())
    }
}
