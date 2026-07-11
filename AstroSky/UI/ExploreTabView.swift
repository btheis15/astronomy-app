//
//  ExploreTabView.swift
//  AstroSky
//
//  Scale AR explorer: pick a scene, place a scale model in your room, and tap
//  the worlds to learn about them.
//

import ARKit
import SwiftUI

struct ExploreTabView: View {
    @State private var scene: ScaleScene = .planet(.saturn)
    @State private var distanceMode: DistanceMode = .fit
    @State private var selected: ScaleBody?
    @State private var isPlaced = false
    /// Height of the model above the placed surface, in meters.
    @State private var heightMeters: Float = 0

    private var isAR: Bool { ARWorldTrackingConfiguration.isSupported }

    var body: some View {
        guard isAR else {
            return AnyView(ContentUnavailableView(
                "AR Not Available",
                systemImage: "xmark.circle",
                description: Text("This device doesn't support ARKit world tracking. The scale model view requires a device with a motion coprocessor.")
            ))
        }
        return AnyView(ZStack {
            ScaleARView(scene: scene, distanceMode: distanceMode, heightMeters: heightMeters,
                        onSelect: { selected = $0 },
                        onPlacementChange: { isPlaced = $0 })
                .id(scene.id)   // rebuild cleanly when the scene changes
                .ignoresSafeArea()

            VStack {
                controls
                Spacer()
                if !isPlaced {
                    Label("Point at the floor or a table, then tap to place",
                          systemImage: "hand.tap")
                        .font(.footnote.weight(.medium))
                        .padding(10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 24)
                } else if isAR {
                    heightControl
                        .padding(.bottom, 20)
                }
            }
            .padding()
        }
        .sheet(item: $selected) { body in
            BodyInfoSheet(model: body)
                .presentationDetents([.medium])
        })
    }

    private var controls: some View {
        HStack {
            Menu {
                ForEach(ScaleScene.all) { option in
                    Button(option.title) { scene = option }
                }
            } label: {
                Label(scene.title, systemImage: "chevron.down.circle")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            Spacer()

            Picker("Scale", selection: $distanceMode) {
                ForEach(DistanceMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    /// Raise the model off the floor so it's comfortable standing outdoors.
    private var heightControl: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.up.and.down")
            Slider(value: $heightMeters, in: 0...1.8)
            Text("\(heightMeters * 3.28084, specifier: "%.1f") ft")
                .font(.caption.monospacedDigit())
                .frame(width: 46, alignment: .trailing)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

private struct BodyInfoSheet: View {
    let model: ScaleBody
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(model.info).font(.body)
                }
                Section("Facts") {
                    LabeledContent("Diameter", value: formatKm(model.radiusKm * 2))
                    if let orbit = model.orbitRadiusKm {
                        LabeledContent("Distance from primary", value: formatKm(orbit))
                    }
                }
            }
            .navigationTitle(model.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func formatKm(_ km: Double) -> String {
        if km >= 1_000_000 {
            return String(format: "%.2f million km", km / 1_000_000)
        }
        return "\(Int(km).formatted()) km"
    }
}
