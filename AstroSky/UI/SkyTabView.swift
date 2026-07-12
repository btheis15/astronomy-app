//
//  SkyTabView.swift
//  AstroSky
//
//  The AR sky: camera passthrough with the celestial overlay, plus HUD
//  controls (search, time travel, mode switch, object card, guidance arrow).
//

import ARKit
import SwiftUI

struct SkyTabView: View {
    @Environment(AppState.self) private var appState
    @State private var guide: GuideReadout?
    @State private var showSearch = false
    @State private var showCalibrationSheet = false
    @State private var trackingHint: String?

    /// Effective display mode: honours the stored preference but falls back to
    /// VR (motion-tracked) when AR isn't available (e.g. Simulator).
    private var effectiveMode: SkyDisplayMode {
        if !ARWorldTrackingConfiguration.isSupported && appState.skyDisplayMode == .ar {
            return .vr
        }
        return appState.skyDisplayMode
    }

    @State private var showTimeControls = false
    @State private var renderer: SkyRenderer?
    @State private var capturedPhoto: CapturedPhoto?
    @State private var isCapturing = false

    var body: some View {
        ZStack {
            SkyARViewContainer(appState: appState,
                               skyDisplayMode: effectiveMode,
                               onGuideUpdate: { guide = $0 },
                               onTrackingHint: { trackingHint = $0 },
                               onRendererReady: { renderer = $0 })
            .id(effectiveMode)   // rebuild the view when switching modes
            .ignoresSafeArea()

            hud
        }
        .sheet(item: $capturedPhoto) { photo in
            ShareSheet(items: [photo.image])
        }
        .onChange(of: appState.selectedObjectID) { _, _ in announceSelection() }
    }

    /// Speak the newly-selected object and its position for VoiceOver users.
    private func announceSelection() {
        guard let object = appState.selectedObject else { return }
        let horizontal = object.horizontal(julianDate: appState.skyJulianDate, observer: appState.observer)
        let message = "Selected \(object.name), altitude \(Int(horizontal.altitudeDegrees)) degrees, \(horizontal.compassDirection)."
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    private func capturePhoto() {
        guard !isCapturing, let renderer else { return }
        isCapturing = true
        Task {
            if let image = await renderer.captureSnapshot() {
                capturedPhoto = CapturedPhoto(image: image)
            }
            isCapturing = false
        }
    }

    private var hud: some View {
        VStack(spacing: 0) {
            topBar

            if let hint = trackingHint {
                Text(hint)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer()

            if let guide, appState.guideTargetID != nil {
                GuideArrowView(guide: guide) {
                    appState.guideTargetID = nil
                }
                .padding(.bottom, 10)
            }

            if !appState.isLiveTime || showTimeControls {
                TimeControlBar(isExpanded: $showTimeControls)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }

            if let selected = appState.selectedObject {
                ObjectCardView(object: selected)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: appState.selectedObjectID)
        .animation(.snappy, value: trackingHint)
        .sheet(isPresented: $showSearch) {
            SearchView()
                .nightModeAware()
        }
    }

    private var topBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                topBarLeading
                Spacer()
                topBarTrailing
            }
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 8) { topBarLeading; Spacer() }
                HStack(spacing: 8) { topBarTrailing }
            }
        }
        .padding(.horizontal)
        .padding(.top, 4)
    }

    @ViewBuilder private var topBarLeading: some View {
        locationBadge
        if let accuracy = appState.locationService.headingAccuracy {
            headingChip(accuracy: accuracy)
        }
    }

    @ViewBuilder private var topBarTrailing: some View {
        if appState.hasAlignmentOffset {
            hudButton(systemImage: "arrow.counterclockwise", label: "Reset sky alignment") {
                withAnimation(.snappy) { appState.resetAlignment() }
            }
        }
        if !appState.isLiveTime {
            Button {
                appState.resetToLiveTime()
            } label: {
                Label("Live", systemImage: "clock.arrow.circlepath")
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        hudButton(systemImage: "clock", label: "Time travel controls") {
            showTimeControls.toggle()
        }
        // Mode menu: shows the current mode icon and lists all three options.
        Menu {
            Button {
                appState.skyDisplayMode = .ar
            } label: {
                if effectiveMode == .ar { Label("AR Camera", systemImage: "checkmark") }
                else { Text("AR Camera") }
            }
            .disabled(!ARWorldTrackingConfiguration.isSupported)

            Button {
                appState.skyDisplayMode = .vr
            } label: {
                if effectiveMode == .vr { Label("Immersive (gyroscope)", systemImage: "checkmark") }
                else { Text("Immersive (gyroscope)") }
            }

            Button {
                appState.skyDisplayMode = .freeLook
            } label: {
                if effectiveMode == .freeLook { Label("Free-look (drag)", systemImage: "checkmark") }
                else { Text("Free-look (drag)") }
            }
        } label: {
            Image(systemName: currentModeIcon)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityLabel("Sky view mode")
        hudButton(systemImage: isCapturing ? "camera.fill" : "camera", label: "Take photo") {
            capturePhoto()
        }
        hudButton(systemImage: "magnifyingglass", label: "Search the sky") {
            showSearch = true
        }
    }

    private var currentModeIcon: String {
        switch effectiveMode {
        case .ar:       return "camera.viewfinder"
        case .vr:       return "moon.stars.fill"
        case .freeLook: return "move.3d"
        }
    }

    private var locationBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: appState.locationService.hasRealLocation
                ? "location.fill" : "location.slash")
            Text(appState.locationService.placeName
                ?? String(format: "%.1f°, %.1f°",
                          appState.observer.latitudeDegrees,
                          appState.observer.longitudeDegrees))
                .lineLimit(1)
        }
        .font(.footnote)
        .frame(minWidth: 80, maxWidth: 220)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }

    /// Compass heading-accuracy chip: green when well-calibrated, amber/red as
    /// it degrades. Tap when red to show calibration instructions.
    private func headingChip(accuracy: Double) -> some View {
        let color: Color = accuracy <= 10 ? .green : (accuracy <= 25 ? .yellow : .red)
        let chip = HStack(spacing: 4) {
            Image(systemName: "safari")
            Text("±\(Int(accuracy.rounded()))°")
                .monospacedDigit()
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .accessibilityLabel("Compass accuracy plus or minus \(Int(accuracy.rounded())) degrees")

        return Group {
            if color == .red {
                Button { showCalibrationSheet = true } label: { chip }
                    .buttonStyle(.plain)
                    .sheet(isPresented: $showCalibrationSheet) {
                        CompassCalibrationSheet()
                            .nightModeAware()
                    }
            } else {
                chip
            }
        }
    }

    private func hudButton(systemImage: String, label: String = "", action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label.isEmpty ? systemImage : label)
    }
}

// MARK: - Compass calibration

private struct CompassCalibrationSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Label("Move away from metal surfaces, magnets, or a magnetic phone case.", systemImage: "exclamationmark.triangle")
                Label("Hold the phone in front of you and slowly rotate your wrist in a figure-8 pattern until the chip turns green.", systemImage: "arrow.triangle.2.circlepath")
                Label("Use the two-finger drag in the sky view to fine-align the overlay after calibrating.", systemImage: "hand.draw")
            }
            .font(.subheadline)
            .padding()
            .navigationTitle("Calibrate Compass")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
