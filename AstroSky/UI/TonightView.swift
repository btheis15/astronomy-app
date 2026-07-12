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
    @State private var eventsLoaded = false
    @State private var twilight: TwilightTimes? = nil
    @State private var moonPhase: MoonEphemeris.PhaseInfo? = nil
    @State private var moonEvents: RiseSetEvents? = nil
    @State private var planetInfos: [(planet: PlanetObject, altStr: String, isUp: Bool, magStr: String)] = []
    @State private var telescopeTargets: [TonightTarget] = []
    @State private var telescopeTargetsLoaded = false

    /// Passes ordered either by time (default) or by peak brightness.
    private var sortedPasses: [SatellitePass] {
        guard brightestFirst else { return passes }
        return passes.sorted { ($0.peakMagnitude ?? 99) < ($1.peakMagnitude ?? 99) }
    }

    /// Day-granularity key to trigger ephemeris computation once per day.
    private var dayKey: Int { Int(Date().timeIntervalSince1970 / 86400) }

    var body: some View {
        NavigationStack {
            List {
                eventsSection
                sunSection
                moonSection
                planetsSection
                telescopeSection
                passesSection
            }
            .navigationTitle("Tonight")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ObservationLogView()
                    } label: {
                        Image(systemName: "book.closed")
                    }
                    .accessibilityLabel("Observing Log")
                }
            }
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
                if !telescopeTargetsLoaded {
                    telescopeTargets = await TonightPlanner.compute(appState: appState)
                    telescopeTargetsLoaded = true
                }
            }
            .task(id: dayKey) {
                let obs = appState.observer
                let dayStart = Calendar.current.startOfDay(for: Date())

                // Twilight computation: expensive bisection, runs off main thread
                twilight = await Task.detached(priority: .utility) {
                    RiseSetCalculator.twilight(observer: obs, startingAt: dayStart)
                }.value

                // Moon phase: fast, compute on main
                moonPhase = MoonEphemeris.phase(julianDate: appState.skyJulianDate)

                // Moon rise/set: expensive bisection, runs off main thread
                moonEvents = await Task.detached(priority: .utility) {
                    RiseSetCalculator.events(startingAt: dayStart,
                                             threshold: RiseSetCalculator.Threshold.moon) { date in
                        let jd = AstroTime.julianDate(date)
                        let eq = MoonEphemeris.position(julianDate: jd).equatorial
                        return CoordinateTransforms.horizontal(of: eq, julianDate: jd, observer: obs).altitude
                    }
                }.value

                // Planets: precompute all info, map to avoid repeated ephemeris calls per row
                let jd = appState.skyJulianDate
                planetInfos = appState.catalog.planets.map { planet in
                    let pos = PlanetEphemeris.position(of: planet.planet, julianDate: jd)
                    let h = planet.horizontal(julianDate: jd, observer: obs)
                    return (planet, AstroFormat.degrees(h.altitude) + " · " + h.compassDirection,
                            h.isAboveHorizon, AstroFormat.magnitude(pos.magnitude))
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
        } else if !eventsLoaded {
            Section("Sky events · next 30 days") {
                HStack {
                    ProgressView()
                    Text("Scanning for events…").foregroundStyle(.secondary)
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
        eventsLoaded = true
    }

    // MARK: Sun & twilight

    private var sunSection: some View {
        Section("Sun & twilight") {
            row("Sunrise", twilight.map { AstroFormat.time($0.sunrise) } ?? "12:00 AM", icon: "sunrise")
                .redacted(reason: twilight == nil ? .placeholder : [])
            row("Sunset", twilight.map { AstroFormat.time($0.sunset) } ?? "12:00 PM", icon: "sunset")
                .redacted(reason: twilight == nil ? .placeholder : [])
            row("Civil dusk", twilight.map { AstroFormat.time($0.civilDusk) } ?? "—", icon: "sun.horizon")
            row("Astronomical dusk", twilight.map { AstroFormat.time($0.astronomicalDusk) } ?? "—", icon: "moon.haze")
            row("Astronomical dawn", twilight.map { AstroFormat.time($0.astronomicalDawn) } ?? "—", icon: "moon.haze.fill")
        }
    }

    // MARK: Moon

    private var moonSection: some View {
        Section("Moon") {
            if let phase = moonPhase {
                NavigationLink {
                    ObjectDetailView(object: appState.catalog.moon)
                } label: {
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
                }
            }

            if let events = moonEvents {
                row("Moonrise", AstroFormat.time(events.rise), icon: "moonrise")
                row("Moonset", AstroFormat.time(events.set), icon: "moonset")
            }
        }
    }

    // MARK: Planets

    private var planetsSection: some View {
        Section("Planets tonight") {
            ForEach(planetInfos, id: \.planet.id) { info in
                NavigationLink {
                    ObjectDetailView(object: info.planet)
                } label: {
                    HStack {
                        PlanetGlyph(planet: info.planet.planet, size: 30).frame(width: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(info.planet.name)
                            Text("mag \(info.magStr)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(info.isUp ? "Up now" : "Below horizon")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(info.isUp ? .green : .secondary)
                            Text(info.altStr)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: Telescope targets

    @ViewBuilder private var telescopeSection: some View {
        Section {
            if !telescopeTargetsLoaded {
                HStack {
                    ProgressView()
                    Text("Finding tonight's targets…").foregroundStyle(.secondary)
                }
            } else if telescopeTargets.isEmpty {
                if appState.activeOptics == nil {
                    NavigationLink { EquipmentEditorView() } label: {
                        Label("Set up a telescope to see tonight's best targets",
                              systemImage: "eyeglasses")
                    }
                }
            } else {
                ForEach(telescopeTargets.prefix(5)) { target in
                    NavigationLink {
                        ObjectDetailView(object: target.object)
                    } label: {
                        HStack {
                            ObjectGlyph(object: target.object, size: 30).frame(width: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(target.object.name)
                                Text(target.object.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(target.verdict.rawValue)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                NavigationLink {
                    ObserveTonightView()
                } label: {
                    Text("See all \(telescopeTargets.count) targets")
                        .font(.subheadline)
                        .foregroundStyle(.indigo)
                }
            }
        } header: {
            Text("Best for your telescope")
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
                SatelliteGlyph(size: 30)
                    .frame(width: 34)
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
        passes = Self.deduplicated(computed)
        passesLoaded = true
    }

    /// Collapse near-simultaneous passes of the same-named satellite. The three
    /// CSS station modules (Tianhe/Wentian/Mengtian) fly together and are
    /// distinct NORAD objects, so they would otherwise list as three identical
    /// "CSS" passes. Keeps the highest-altitude of each overlapping group.
    private static func deduplicated(_ passes: [SatellitePass]) -> [SatellitePass] {
        var kept: [SatellitePass] = []
        for pass in passes {
            if let index = kept.firstIndex(where: {
                $0.satelliteName == pass.satelliteName
                    && pass.start <= $0.end.addingTimeInterval(60)
                    && $0.start <= pass.end.addingTimeInterval(60)
            }) {
                if pass.maxAltitude > kept[index].maxAltitude { kept[index] = pass }
            } else {
                kept.append(pass)
            }
        }
        return kept
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
