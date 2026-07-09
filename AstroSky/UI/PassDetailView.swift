//
//  PassDetailView.swift
//  AstroSky
//
//  Detail of a single satellite pass: a polar alt-azimuth sky chart of the
//  track (north up) with start/peak/end markers, plus the numbers that matter
//  for actually catching it — times, rise/set compass points, peak altitude,
//  duration and range.
//

import SwiftUI

struct PassDetailView: View {
    @Environment(AppState.self) private var appState
    let pass: SatellitePass

    private var satellite: Satellite? {
        appState.satelliteService.satellite(withID: pass.satelliteID)
    }

    /// Alt/az samples across the pass (every ~10 s), above the horizon.
    private var samples: [PassSample] {
        guard let satellite else { return [] }
        let observer = appState.observer
        let total = pass.end.timeIntervalSince(pass.start)
        guard total > 0 else { return [] }
        let step = max(5.0, total / 80.0)
        var result: [PassSample] = []
        var t = pass.start.timeIntervalSince1970
        let end = pass.end.timeIntervalSince1970
        while t <= end {
            let date = Date(timeIntervalSince1970: t)
            let jd = AstroTime.julianDate(date)
            if let observation = satellite.observe(julianDate: jd, observer: observer),
               observation.horizontal.altitude > -0.02 {
                result.append(PassSample(date: date, horizontal: observation.horizontal))
            }
            t += step
        }
        return result
    }

    var body: some View {
        List {
            Section {
                PassSkyChart(samples: samples,
                             start: pass.start, peak: pass.peak, end: pass.end)
                    .frame(height: 300)
                    .listRowInsets(EdgeInsets())
                    .padding(.vertical, 8)
            }

            Section("Pass") {
                row("Starts", "\(AstroFormat.time(pass.start)) · \(compass(at: pass.start))")
                row("Peak", "\(AstroFormat.time(pass.peak)) · \(AstroFormat.degrees(pass.maxAltitude))")
                row("Ends", "\(AstroFormat.time(pass.end)) · \(compass(at: pass.end))")
                row("Duration", durationString)
                if let range = rangeAtPeakKm {
                    row("Range at peak", String(format: "%.0f km", range))
                }
                if let magnitude = pass.peakMagnitude {
                    row("Peak brightness", "mag \(String(format: "%.1f", magnitude))")
                }
            }
        }
        .navigationTitle(pass.satelliteName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if let satellite {
                        appState.select(satellite)
                        appState.guideTargetID = satellite.id
                        appState.skyTabRequested = true
                    }
                } label: {
                    Label("Find in AR", systemImage: "arkit")
                }
            }
        }
    }

    private var durationString: String {
        let seconds = Int(pass.end.timeIntervalSince(pass.start))
        return "\(seconds / 60) min \(seconds % 60) s"
    }

    private var rangeAtPeakKm: Double? {
        satellite?.observe(julianDate: AstroTime.julianDate(pass.peak),
                           observer: appState.observer)?.rangeKm
    }

    private func compass(at date: Date) -> String {
        guard let satellite,
              let observation = satellite.observe(julianDate: AstroTime.julianDate(date),
                                                  observer: appState.observer) else { return "—" }
        return observation.horizontal.compassDirection
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.subheadline)
    }
}

private struct PassSample: Identifiable {
    let date: Date
    let horizontal: HorizontalCoordinates
    var id: Date { date }
}

/// Polar alt-azimuth chart: horizon at the rim, zenith at the center, north up.
private struct PassSkyChart: View {
    let samples: [PassSample]
    let start: Date
    let peak: Date
    let end: Date

    var body: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) / 2 - 22
            let center = CGPoint(x: size.width / 2, y: size.height / 2)

            // Altitude rings (0°, 30°, 60°) and cardinal spokes.
            let ringColor = GraphicsContext.Shading.color(.gray.opacity(0.35))
            for altitude in [0.0, 30.0, 60.0] {
                let r = radius * (90 - altitude) / 90
                let rect = CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)
                context.stroke(Path(ellipseIn: rect), with: ringColor, lineWidth: altitude == 0 ? 1.5 : 0.5)
            }
            for (label, azimuth) in [("N", 0.0), ("E", 90.0), ("S", 180.0), ("W", 270.0)] {
                let edge = point(altitudeDegrees: 0, azimuthDegrees: azimuth, center: center, radius: radius)
                context.stroke(Path { $0.move(to: center); $0.addLine(to: edge) },
                               with: .color(.gray.opacity(0.2)), lineWidth: 0.5)
                let labelPoint = point(altitudeDegrees: -8, azimuthDegrees: azimuth, center: center, radius: radius)
                context.draw(Text(label).font(.caption2).foregroundStyle(.secondary),
                             at: labelPoint)
            }

            guard samples.count > 1 else { return }

            // Track polyline.
            var path = Path()
            for (index, sample) in samples.enumerated() {
                let p = point(altitudeDegrees: sample.horizontal.altitudeDegrees,
                              azimuthDegrees: sample.horizontal.azimuthDegrees,
                              center: center, radius: radius)
                if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            context.stroke(path, with: .color(.green), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

            // Start / peak / end markers.
            marker(context, at: samples.first!, center: center, radius: radius, color: .cyan, label: "Start")
            if let peakSample = samples.min(by: {
                abs($0.date.timeIntervalSince(peak)) < abs($1.date.timeIntervalSince(peak))
            }) {
                marker(context, at: peakSample, center: center, radius: radius, color: .yellow, label: "Peak")
            }
            marker(context, at: samples.last!, center: center, radius: radius, color: .orange, label: "End")
        }
    }

    private func marker(_ context: GraphicsContext, at sample: PassSample,
                        center: CGPoint, radius: CGFloat, color: Color, label: String) {
        let p = point(altitudeDegrees: sample.horizontal.altitudeDegrees,
                      azimuthDegrees: sample.horizontal.azimuthDegrees,
                      center: center, radius: radius)
        let dot = CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)
        context.fill(Path(ellipseIn: dot), with: .color(color))
        context.draw(Text(label).font(.caption2.weight(.semibold)).foregroundStyle(color),
                     at: CGPoint(x: p.x, y: p.y - 14))
    }

    /// Map alt/az to a point: zenith at center, horizon at the rim, north up,
    /// azimuth increasing clockwise (east to the right).
    private func point(altitudeDegrees: Double, azimuthDegrees: Double,
                       center: CGPoint, radius: CGFloat) -> CGPoint {
        let r = radius * CGFloat((90 - altitudeDegrees) / 90)
        let a = azimuthDegrees * .pi / 180
        return CGPoint(x: center.x + r * CGFloat(sin(a)),
                       y: center.y - r * CGFloat(cos(a)))
    }
}
