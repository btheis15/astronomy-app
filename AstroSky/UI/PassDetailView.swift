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

    // MARK: - Cached expensive computations

    /// All SGP4-derived data for this pass, computed once in a .task.
    private struct PassData {
        var samples: [PassSample]
        var startCompass: String
        var endCompass: String
        var rangeAtPeakKm: Double?
    }

    @State private var passData: PassData = PassData(samples: [], startCompass: "—",
                                                     endCompass: "—", rangeAtPeakKm: nil)

    /// Stable key: the pass identity never changes, so we compute exactly once.
    private var passKey: String {
        "\(pass.satelliteID)|\(pass.start.timeIntervalSince1970)"
    }

    var body: some View {
        List {
            Section {
                PassSkyChart(samples: passData.samples,
                             start: pass.start, peak: pass.peak, end: pass.end)
                    .frame(height: 300)
                    .listRowInsets(EdgeInsets())
                    .padding(.vertical, 8)
            }

            Section("Pass") {
                DetailRow(label: "Starts", value: "\(AstroFormat.time(pass.start)) · \(passData.startCompass)")
                DetailRow(label: "Peak", value: "\(AstroFormat.time(pass.peak)) · \(AstroFormat.degrees(pass.maxAltitude))")
                DetailRow(label: "Ends", value: "\(AstroFormat.time(pass.end)) · \(passData.endCompass)")
                DetailRow(label: "Duration", value: durationString)
                if let range = passData.rangeAtPeakKm {
                    DetailRow(label: "Range at peak", value: String(format: "%.0f km", range))
                }
                if let magnitude = pass.peakMagnitude {
                    DetailRow(label: "Peak brightness", value: "mag \(String(format: "%.1f", magnitude))")
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
        // Compute all SGP4-derived data once (the pass is immutable).
        .task(id: passKey) {
            guard let satellite else { return }
            let observer = appState.observer
            let passStart = pass.start
            let passEnd = pass.end
            let passPeak = pass.peak

            passData = await Task.detached(priority: .userInitiated) {
                // Build alt/az track samples (~80 SGP4 propagations).
                let total = passEnd.timeIntervalSince(passStart)
                var samples: [PassSample] = []
                if total > 0 {
                    let step = max(5.0, total / 80.0)
                    var t = passStart.timeIntervalSince1970
                    let end = passEnd.timeIntervalSince1970
                    while t <= end {
                        let date = Date(timeIntervalSince1970: t)
                        let jd = AstroTime.julianDate(date)
                        if let observation = satellite.observe(julianDate: jd, observer: observer),
                           observation.horizontal.altitude > -0.02 {
                            samples.append(PassSample(date: date, horizontal: observation.horizontal))
                        }
                        t += step
                    }
                }

                // Compass directions at rise and set.
                func compass(at date: Date) -> String {
                    guard let obs = satellite.observe(julianDate: AstroTime.julianDate(date),
                                                      observer: observer) else { return "—" }
                    return obs.horizontal.compassDirection
                }
                let startCompass = compass(at: passStart)
                let endCompass = compass(at: passEnd)

                // Range at peak.
                let rangeAtPeakKm = satellite.observe(julianDate: AstroTime.julianDate(passPeak),
                                                      observer: observer)?.rangeKm

                return PassData(samples: samples,
                                startCompass: startCompass,
                                endCompass: endCompass,
                                rangeAtPeakKm: rangeAtPeakKm)
            }.value
        }
    }

    private var durationString: String {
        let seconds = Int(pass.end.timeIntervalSince(pass.start))
        return "\(seconds / 60) min \(seconds % 60) s"
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

    /// Direction label for the first/last sample, e.g. "northeast".
    private func compassLabel(for sample: PassSample) -> String {
        let az = sample.horizontal.azimuthDegrees
        switch az {
        case 0..<22.5, 337.5..<360: return "north"
        case 22.5..<67.5:           return "northeast"
        case 67.5..<112.5:          return "east"
        case 112.5..<157.5:         return "southeast"
        case 157.5..<202.5:         return "south"
        case 202.5..<247.5:         return "southwest"
        case 247.5..<292.5:         return "west"
        default:                    return "northwest"
        }
    }

    private var accessibilityDescription: String {
        guard let first = samples.first, let last = samples.last else {
            return "Sky chart showing satellite pass track"
        }
        let peakSample = samples.min { abs($0.date.timeIntervalSince(peak)) < abs($1.date.timeIntervalSince(peak)) }
        let peakAlt = peakSample.map { Int($0.horizontal.altitudeDegrees.rounded()) } ?? 0
        let riseDir = compassLabel(for: first)
        let setDir = compassLabel(for: last)
        return "Sky chart: satellite rises in the \(riseDir), peaks at \(peakAlt) degrees altitude, sets in the \(setDir)"
    }

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
        .accessibilityLabel(accessibilityDescription)
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
