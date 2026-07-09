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
    @State private var preferManualMode = !ARWorldTrackingConfiguration.isSupported
    @State private var showSearch = false
    @State private var showTimeControls = false
    @State private var renderer: SkyRenderer?
    @State private var capturedPhoto: CapturedPhoto?
    @State private var isCapturing = false

    var body: some View {
        ZStack {
            SkyARViewContainer(appState: appState,
                               preferManualMode: preferManualMode,
                               onGuideUpdate: { guide = $0 },
                               onRendererReady: { renderer = $0 })
            .id(preferManualMode)   // rebuild the view when switching modes
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
        .sheet(isPresented: $showSearch) {
            SearchView()
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            locationBadge

            if let accuracy = appState.locationService.headingAccuracy {
                headingChip(accuracy: accuracy)
            }

            Spacer()

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
            hudButton(systemImage: preferManualMode ? "arkit" : "hand.draw",
                      label: preferManualMode ? "Switch to AR mode" : "Switch to manual look-around mode") {
                preferManualMode.toggle()
            }
            hudButton(systemImage: isCapturing ? "camera.fill" : "camera", label: "Take photo") {
                capturePhoto()
            }
            hudButton(systemImage: "magnifyingglass", label: "Search the sky") {
                showSearch = true
            }
        }
        .padding(.horizontal)
        .padding(.top, 4)
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
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }

    /// Compass heading-accuracy chip: green when well-calibrated, amber/red as
    /// it degrades. Tapping isn't needed — it's a passive calibration cue.
    private func headingChip(accuracy: Double) -> some View {
        let color: Color = accuracy <= 15 ? .green : (accuracy <= 30 ? .yellow : .red)
        return HStack(spacing: 4) {
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

// MARK: - Photo capture & share

struct CapturedPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// UIKit share-sheet bridge.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - Guidance arrow

struct GuideArrowView: View {
    let guide: GuideReadout
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            if guide.isOnTarget {
                Label("On target: \(guide.targetName)", systemImage: "scope")
                    .font(.subheadline.weight(.semibold))
            } else {
                Image(systemName: "arrow.right")
                    .font(.system(size: 34, weight: .bold))
                    // Screen angle: 0 = right, π/2 = up; SwiftUI rotation is
                    // clockwise, so negate.
                    .rotationEffect(.radians(-guide.arrowAngle))
                Text(guide.isBelowHorizon
                    ? "\(guide.targetName) is below the horizon"
                    : "Turn toward \(guide.targetName)")
                    .font(.footnote)
            }
            Button("Stop guiding", action: onDismiss)
                .font(.caption)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .foregroundStyle(guide.isOnTarget ? .green : .primary)
    }
}

// MARK: - Time travel

struct TimeControlBar: View {
    @Environment(AppState.self) private var appState
    @Binding var isExpanded: Bool

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

            Slider(value: $appState.timeOffset, in: -43_200...43_200, step: 300) {
                Text("Time offset")
            } minimumValueLabel: {
                Text("−12h").font(.caption2)
            } maximumValueLabel: {
                Text("+12h").font(.caption2)
            }

            HStack(spacing: 10) {
                timeJumpButton("−1d", seconds: -86_400)
                timeJumpButton("−1h", seconds: -3600)
                timeJumpButton("+1h", seconds: 3600)
                timeJumpButton("+1d", seconds: 86_400)
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

// MARK: - Selected object card

struct ObjectCardView: View {
    @Environment(AppState.self) private var appState
    let object: any CelestialObject
    @State private var showDetail = false

    var body: some View {
        let position = object.skyPosition(julianDate: appState.skyJulianDate,
                                          observer: appState.observer)
        HStack(spacing: 12) {
            Image(systemName: object.kind.iconSystemName)
                .font(.title2)
                .foregroundStyle(.yellow)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(object.name).font(.headline)
                Text(object.subtitle).font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Label(AstroFormat.degrees(position.horizontal.altitude), systemImage: "arrow.up.and.down")
                    Label(AstroFormat.azimuth(position.horizontal), systemImage: "safari")
                    if let magnitude = object.magnitude {
                        Label(AstroFormat.magnitude(magnitude), systemImage: "sun.max")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(spacing: 8) {
                Button {
                    showDetail = true
                } label: {
                    Image(systemName: "info.circle").font(.title3)
                }
                Button {
                    appState.select(nil)
                } label: {
                    Image(systemName: "xmark.circle").font(.title3)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .sheet(isPresented: $showDetail) {
            NavigationStack {
                ObjectDetailView(object: object)
            }
        }
    }
}
