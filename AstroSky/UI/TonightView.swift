//
//  TonightView.swift
//  AstroSky
//
//  "What's up tonight": sun & twilight times, moon phase, visible planets
//  and upcoming bright satellite passes.
//

import SwiftUI

struct TonightView: View {
    @Environment(AppState.self) private var appState
    @State private var passes: [SatellitePass] = []
    @State private var passesLoaded = false
    @State private var brightestFirst = false
    @State private var events: [AstroEvent] = []

    /// Passes ordered either by time (default) or by peak brightness.
    private var sortedPasses: [SatellitePass] {
        guard brightestFirst else { return passes }
        return passes.sorted { ($0.peakMagnitude ?? 99) < ($1.peakMagnitude ?? 99) }
    }

    var body: some View {
        NavigationStack {
            List {
                eventsSection
                sunSection
                moonSection
                planetsSection
                passesSection
            }
            .navigationTitle("Tonight")
            .refreshable {
                await appState.satelliteService.refresh()
                await reloadPasses()
            }
            .task {
                if !passesLoaded {
                    await reloadPasses()
                }
                if events.isEmpty {
                    await reloadEvents()
                }
            }
        }
    }

    // MARK: Events

    @ViewBuilder private var eventsSection: some View {
        if !events.isEmpty {
            Section("Sky events · next 30 days") {
                ForEach(events.prefix(8)) { event in
                    HStack(spacing: 12) {
                        Image(systemName: event.kind.iconSystemName)
                            .foregroundStyle(.yellow)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title)
                            Text(event.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(event.date.formatted(.dateTime.month().day()))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func reloadEvents() async {
        let observer = appState.observer
        let start = Date()
        events = await Task.detached(priority: .utility) {
            EventsEngine.upcoming(observer: observer, startingAt: start, days: 30)
        }.value
    }

    // MARK: Sun & twilight

    private var sunSection: some View {
        let dayStart = Calendar.current.startOfDay(for: Date())
        let twilight = RiseSetCalculator.twilight(observer: appState.observer, startingAt: dayStart)
        return Section("Sun & twilight") {
            row("Sunrise", AstroFormat.time(twilight.sunrise), icon: "sunrise")
            row("Sunset", AstroFormat.time(twilight.sunset), icon: "sunset")
            row("Civil dusk", AstroFormat.time(twilight.civilDusk), icon: "sun.horizon")
            row("Astronomical dusk", AstroFormat.time(twilight.astronomicalDusk), icon: "moon.haze")
            row("Astronomical dawn", AstroFormat.time(twilight.astronomicalDawn), icon: "moon.haze.fill")
        }
    }

    // MARK: Moon

    private var moonSection: some View {
        let jd = appState.skyJulianDate
        let phase = MoonEphemeris.phase(julianDate: jd)
        let dayStart = Calendar.current.startOfDay(for: Date())
        let observer = appState.observer
        let events = RiseSetCalculator.events(startingAt: dayStart,
                                              threshold: RiseSetCalculator.Threshold.moon) { date in
            let jd = AstroTime.julianDate(date)
            let eq = MoonEphemeris.position(julianDate: jd).equatorial
            return CoordinateTransforms.horizontal(of: eq, julianDate: jd, observer: observer).altitude
        }

        return Section("Moon") {
            HStack(spacing: 16) {
                MoonPhaseView(phase: phase)
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(phase.phaseName).font(.headline)
                    Text("\(Int((phase.illuminatedFraction * 100).rounded()))% illuminated")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture { appState.select(appState.catalog.moon) }

            row("Moonrise", AstroFormat.time(events.rise), icon: "moonrise")
            row("Moonset", AstroFormat.time(events.set), icon: "moonset")
        }
    }

    // MARK: Planets

    private var planetsSection: some View {
        Section("Planets tonight") {
            ForEach(appState.catalog.planets, id: \.id) { planet in
                NavigationLink {
                    ObjectDetailView(object: planet)
                } label: {
                    planetRow(planet)
                }
            }
        }
    }

    private func planetRow(_ planet: PlanetObject) -> some View {
        let jd = appState.skyJulianDate
        let position = PlanetEphemeris.position(of: planet.planet, julianDate: jd)
        let horizontal = planet.horizontal(julianDate: jd, observer: appState.observer)
        return HStack {
            Text(planet.planet.symbol).font(.title3).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(planet.name)
                Text("mag \(AstroFormat.magnitude(position.magnitude))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(horizontal.isAboveHorizon ? "Up now" : "Below horizon")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(horizontal.isAboveHorizon ? .green : .secondary)
                Text("\(AstroFormat.degrees(horizontal.altitude)) · \(horizontal.compassDirection)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Satellite passes

    private var passesSection: some View {
        Section {
            switch appState.satelliteService.state {
            case .loading where passes.isEmpty:
                HStack {
                    ProgressView()
                    Text("Fetching satellite data…").foregroundStyle(.secondary)
                }
            case .failed(let message) where passes.isEmpty:
                Label(message, systemImage: "wifi.slash").foregroundStyle(.secondary)
            default:
                if passes.isEmpty {
                    Text(passesLoaded
                        ? "No bright passes in the next 24 hours."
                        : "Computing passes…")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedPasses.prefix(8)) { pass in
                        passRow(pass)
                    }
                }
            }
        } header: {
            HStack {
                Text("Visible satellite passes · next 24h")
                Spacer()
                if !passes.isEmpty {
                    Picker("Sort", selection: $brightestFirst) {
                        Text("Time").tag(false)
                        Text("Brightest").tag(true)
                    }
                    .pickerStyle(.menu)
                    .textCase(nil)
                }
            }
        } footer: {
            Text("Passes where the satellite is sunlit against a dark sky, ≥ 10° up.")
        }
    }

    private func passRow(_ pass: SatellitePass) -> some View {
        NavigationLink {
            PassDetailView(pass: pass)
        } label: {
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.green)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pass.satelliteName).foregroundStyle(.primary)
                    Text("\(AstroFormat.time(pass.start)) → \(AstroFormat.time(pass.end))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("max \(AstroFormat.degrees(pass.maxAltitude))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if let magnitude = pass.peakMagnitude {
                        Text("mag \(magnitude, specifier: "%.1f")")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func reloadPasses() async {
        let observer = appState.observer
        let candidates = Array(appState.satelliteService.featured.prefix(12))
        // Pass prediction samples tens of thousands of SGP4 states — keep it
        // off the main actor.
        let computed = await Task.detached(priority: .userInitiated) {
            var all: [SatellitePass] = []
            for satellite in candidates {
                all.append(contentsOf: satellite.passes(observer: observer,
                                                        startingAt: Date(),
                                                        hours: 24))
            }
            return all.filter(\.isVisible).sorted { $0.start < $1.start }
        }.value
        passes = computed
        passesLoaded = true
    }

    private func row(_ label: String, _ value: String, icon: String) -> some View {
        HStack {
            Label(label, systemImage: icon).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.subheadline)
    }
}

// MARK: - Moon phase drawing

struct MoonPhaseView: View {
    let phase: MoonEphemeris.PhaseInfo

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
            let radius = min(rect.width, rect.height) / 2
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let darkColor = Color(white: 0.22)
            let litColor = Color(white: 0.92)

            // 1. Dark disk.
            context.fill(Path(ellipseIn: rect), with: .color(darkColor))

            // 2. Lit semicircle — right side while waxing (northern-sky
            //    convention), left side while waning.
            let fraction = phase.illuminatedFraction
            var semicircle = Path()
            semicircle.addArc(center: center, radius: radius,
                              startAngle: .degrees(-90), endAngle: .degrees(90),
                              clockwise: !phase.isWaxing)
            semicircle.closeSubpath()
            context.fill(semicircle, with: .color(litColor))

            // 3. Terminator ellipse: bulges lit when gibbous, dark when
            //    crescent — overpainting yields the correct phase shape.
            let terminatorWidth = 2 * radius * CGFloat(abs(2 * fraction - 1))
            let terminatorRect = CGRect(x: center.x - terminatorWidth / 2,
                                        y: center.y - radius,
                                        width: terminatorWidth,
                                        height: 2 * radius)
            context.fill(Path(ellipseIn: terminatorRect),
                         with: .color(fraction > 0.5 ? litColor : darkColor))
        }
        .accessibilityLabel("\(phase.phaseName), \(Int(phase.illuminatedFraction * 100)) percent illuminated")
    }
}
