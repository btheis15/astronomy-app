//
//  OnboardingView.swift
//  AstroSky
//
//  Three-page first-launch flow that explains why the app needs the camera
//  and location, and how to calibrate the compass, requesting each permission
//  in context. Shown exactly once (gated by AppState.hasOnboarded).
//

import AVFoundation
import CoreLocation
import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    let onFinish: () -> Void

    @State private var page = 0
    @State private var cameraDenied = false
    @State private var locationDenied = false

    var body: some View {
        VStack {
            HStack {
                Spacer()
                Button("Skip") { finish() }
                    .font(.subheadline)
                    .padding()
            }

            TabView(selection: $page) {
                OnboardingPage(
                    systemImage: "camera.viewfinder",
                    title: "See the real sky",
                    message: "AstroSky overlays stars, planets and satellites on your camera view, so what's on screen lines up with what's above you.",
                    actionTitle: "Enable Camera",
                    action: {
                        await requestCamera()
                        let status = AVCaptureDevice.authorizationStatus(for: .video)
                        if status == .denied || status == .restricted {
                            cameraDenied = true
                        } else {
                            advance()
                        }
                    }
                ).tag(0)

                OnboardingPage(
                    systemImage: "location.viewfinder",
                    title: "Where you're standing",
                    message: "Your rough location lets AstroSky compute exactly where each object appears in your sky tonight.",
                    actionTitle: "Enable Location",
                    action: {
                        appState.locationService.requestLocation()
                        // Give the location manager a brief moment to receive the response
                        try? await Task.sleep(for: .milliseconds(500))
                        let status = appState.locationService.authorizationStatus
                        if status == .denied || status == .restricted {
                            locationDenied = true
                        } else {
                            advance()
                        }
                    }
                ).tag(1)

                OnboardingPage(
                    systemImage: "gyroscope",
                    title: "Calibrate your compass",
                    message: "For an accurate overlay, wave your phone in a figure-8 a couple of times, then point it at the sky. You can fine-tune alignment any time with a two-finger drag.",
                    actionTitle: "Start exploring",
                    action: { finish() }
                ).tag(2)
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .alert("Camera Access Denied", isPresented: $cameraDenied) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Continue Anyway") { advance() }
            } message: {
                Text("Camera access is needed for the AR sky view. You can enable it later in Settings. The immersive (gyroscope) mode works without a camera.")
            }
            .alert("Location Access Denied", isPresented: $locationDenied) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Continue Anyway") { advance() }
            } message: {
                Text("Location lets AstroSky compute exactly where each object is in your sky. You can enable it later in Settings, or enter coordinates manually.")
            }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private func advance() {
        withAnimation { page = min(page + 1, 2) }
    }

    private func finish() {
        appState.hasOnboarded = true
        onFinish()
    }

    private func requestCamera() async {
        _ = await AVCaptureDevice.requestAccess(for: .video)
    }
}

private struct OnboardingPage: View {
    let systemImage: String
    let title: String
    let message: String
    let actionTitle: String
    let action: () async -> Void
    @ScaledMetric private var heroIconSize: CGFloat = 72

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: systemImage)
                .font(.system(size: heroIconSize))
                .foregroundStyle(.indigo)
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .font(.title.weight(.bold))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Button {
                Task { await action() }
            } label: {
                Text(actionTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }
}
