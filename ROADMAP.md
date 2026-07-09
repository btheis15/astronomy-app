# AstroSky — Road to World-Class

A backlog of improvements designed to be executed **by AI coding agents working in parallel**. Every task is self-contained, lists exactly which files it touches, and has acceptance criteria an agent can verify without human judgment.

---

## How to run these tasks with parallel agents

1. **One task = one branch = one PR.** Branch from `main`, name it `feature/<task-id>` (e.g. `feature/A2-star-sprites`).
2. **Give the agent this exact context**, plus the task block below:
   > You are working on AstroSky, a SwiftUI + ARKit/RealityKit iOS astronomy app. Read `README.md` first, then the files listed under "Files" for your task. Match the existing code style (doc comments citing sources, no third-party dependencies unless the task says otherwise, `@Observable`/`@MainActor` patterns as in `AppState.swift`). Build with `xcodebuild -project AstroSky.xcodeproj -scheme AstroSky -destination 'generic/platform=iOS Simulator' build` and run tests with `-scheme AstroSky test` on an iOS Simulator destination before opening a PR.
3. **Respect the conflict groups.** Tasks in the same ⚠️ conflict group touch the same files — run them sequentially or merge between them. Tasks in different groups are safe in parallel.
4. **Do P0 first, alone.** Everything else assumes the app compiles.

### Conflict groups
| Group | Shared files | Tasks |
|---|---|---|
| G-RENDER | `AR/SkySceneBuilder.swift`, `AR/SkyRenderer.swift` | A1, A2, A3, A4, A5, A6 |
| G-ENGINE | `Core/Astronomy/*` | B1, B2, B3 |
| G-CATALOG | `Core/Catalog/*` | B4, B5 |
| G-SAT | `Core/Satellites/*`, `UI/TonightView.swift` | C1, C2, C3 |
| G-UI | `UI/*` (per-file, see tasks) | D1–D6 mostly disjoint |
| G-EXT | new targets/files only | E1, E2, E3, E4 |
| G-INFRA | project/config files | F1, F2, F3 |

---

## P0 — Gate task (run first, alone)

### P0: First-build fixes
- **Effort:** S–M · **Files:** anywhere the compiler complains
- The app was written without access to a compiler. Build the app target and the test target; fix every compile error and warning with the *minimal* change that preserves the documented intent (each file's header comment states its contract). Run the full test suite; all tests must pass. Do not refactor while fixing.
- **Accept:** `xcodebuild … build` exits 0 with zero warnings in `AstroSky/`; `xcodebuild … test` all green.

---

## A. Rendering & AR polish (make the sky beautiful)

### A1: Round, glowing star sprites
- **Effort:** M · **Group:** G-RENDER
- Stars currently render as tangent square quads with flat `UnlitMaterial`. Generate a soft radial-gradient circle texture at runtime (Core Graphics → `TextureResource`), add UVs to the star quads in `SkySceneBuilder.appendQuad`, and apply it via `UnlitMaterial` with `opacityThreshold`/alpha blending so stars are round with a gentle glow. Brightest stars (mag < 0.5) get a subtle 4-point diffraction-spike texture variant.
- **Accept:** stars visibly round in screenshot; frame rate ≥ 55 fps with mag limit 6.5 (Instruments or `arView.debugOptions .showStatistics`).

### A2: Milky Way band
- **Effort:** M · **Group:** G-RENDER
- Render the Milky Way as a translucent textured band. Either procedurally (a wide great-circle ribbon along the galactic plane — galactic north pole at RA 12h51.4m, Dec +27.13°, brightness falloff with galactic latitude) or with a bundled equirectangular texture on an inward-facing sphere. Toggle in Settings (`AppState` + `SettingsView`), default on, and it must dim with the `magnitudeLimit` slider.
- **Accept:** band visible arcing through Cygnus/Sagittarius at correct orientation; toggle works live.

### A3: Sky-coordinate grid & ecliptic line
- **Effort:** S · **Group:** G-RENDER
- Add toggleable great-circle overlays: celestial equator, ecliptic (23.44° tilt through the equinoxes), and an RA/Dec grid (2h × 15° spacing, thinner lines). Reuse `appendGreatCircleSegment`. Three independent toggles in Settings; labels "Ecliptic"/"Equator" placed with `makeLabel`.
- **Accept:** planets and Moon all sit within ~8° of the drawn ecliptic; toggles work live.

### A4: Satellite trails & orbit paths
- **Effort:** M · **Group:** G-SAT + G-RENDER ⚠️ (touches both)
- When a satellite is selected, draw its predicted sky track for ±10 minutes (sample `observe()` every 15 s, draw as a fading polyline in the world frame) with an arrowhead showing direction of motion. Update the track when time-travel changes.
- **Accept:** selecting the ISS shows a smooth arc; the ISS marker moves along it.

### A5: Compass calibration & alignment UX
- **Effort:** M · **Group:** G-RENDER
- `.gravityAndHeading` heading can be off by several degrees. Add (1) a heading-accuracy chip in the Sky HUD fed from `CLLocationManager.heading.headingAccuracy` (LocationService already exists); (2) a manual fine-align mode: a two-finger horizontal drag rotates the whole sky overlay about the zenith axis (store the offset in `AppState`, apply it in `SkyRenderer.tick` on top of `skyOrientation`), with a "Reset alignment" button.
- **Accept:** two-finger drag visibly rotates overlay in AR mode only; offset survives tab switches; reset works.

### A6: Dynamic label decluttering
- **Effort:** M · **Group:** G-RENDER
- All labels currently render at fixed density. Scale label visibility with camera FOV/zoom: in manual mode when FOV < 40°, show star labels down to mag 3.5 and all Messier designations; at FOV > 60° show only mag ≤ 1.5 star labels and constellation names. Implement by bucketing label entities at build time and toggling `isEnabled` in `tick()`.
- **Accept:** zooming in (pinch, manual mode) reveals more labels; no overlap of >2 labels at default FOV in a dense field (screenshot check in Orion).

## B. Astronomy engine depth (make it *accurate* and *deep*)

### B1: Apparent places — nutation & aberration
- **Effort:** M · **Group:** G-ENGINE
- Add nutation in longitude/obliquity (Meeus ch. 22, the 1980 IAU series truncated to the 13 largest terms) and annual aberration (Meeus ch. 23, κ = 20.49552″). Apply to Sun/Moon/planet apparent positions and add apparent sidereal time (GMST + Δψ·cos ε). Extend `AstronomyEngineTests` with Meeus example 22.a (JD 2446895.5: Δψ ≈ −3.788″, Δε ≈ +9.443″).
- **Accept:** new tests pass; Venus test tolerance in `PlanetTests` tightens from 0.2° to 0.05°.

### B2: Comets & bright asteroids
- **Effort:** L · **Group:** G-ENGINE + new files
- Add `Core/Astronomy/MinorBodies.swift`: Keplerian propagation from osculating elements (reuse `AstroMath.solveKepler`; add hyperbolic/near-parabolic solver for comets). Fetch current elements from JPL SBDB or the Minor Planet Center for a curated list (1 Ceres, 4 Vesta, 2 Pallas + any comet brighter than mag 12), with the same disk-cache pattern as `SatelliteService`. New `MinorBodyObject: CelestialObject`, markers in AR, section in Catalog.
- **Accept:** Ceres RA/Dec within 0.5° of JPL Horizons for today's date (hardcode one fixture); objects searchable and tappable.

### B3: Events engine — conjunctions, eclipses, meteor showers
- **Effort:** L · **Group:** G-ENGINE + new files
- New `Core/Astronomy/Events.swift`: scan the next 30 days for (1) Moon–planet and planet–planet conjunctions < 2° (sample separations daily, refine by golden-section); (2) full/new moon instants; (3) lunar/solar eclipses (test Sun–Moon node geometry at new/full moon, Meeus ch. 54 criteria — listing is enough, no path maps); (4) annual meteor showers from a hardcoded IMO table (Quadrantids, Lyrids, Eta Aquariids, Perseids, Orionids, Leonids, Geminids: dates, radiant RA/Dec, ZHR) with radiant markers in AR while active. Add an "Events" section at the top of the Tonight tab.
- **Accept:** unit test finds the next full moon within 1 hour of a known value; Perseids radiant appears Aug 10–15 in AR.

### B4: Caldwell + NGC highlights catalog
- **Effort:** M · **Group:** G-CATALOG
- Add the 109-object Caldwell catalog (same shape as `MessierCatalog`; real J2000 data — agent must source values carefully, e.g. from the canonical Caldwell list) plus ~40 famous NGC objects not in either (Double Cluster, NGC 253, 47 Tuc, ω Cen, Eta Carinae Nebula, Tarantula…). Extend `DeepSkyObject` with an optional `catalog` tag, wire into search, Catalog tab, and AR markers (reuse `buildDeepSkyMarkers`, color by type).
- **Accept:** `CatalogIntegrityTests`-style test: 109 unique Caldwell numbers, valid coordinates, resolvable constellations; "C14" and "Double Cluster" both searchable.

### B5: Sky-brightness model (light pollution & extinction)
- **Effort:** M · **Group:** G-CATALOG + `AppState`
- Add a Bortle-class picker (1–9) in Settings. Derive the effective naked-eye limiting magnitude (Bortle 1 → 7.5 … Bortle 9 → 4.0), cap the star `magnitudeLimit` accordingly, and dim stars near the horizon with airmass extinction (0.28 mag/airmass, Kasten-Young airmass) by bucketing per-altitude opacity in the renderer tick.
- **Accept:** switching Bortle 9 → 1 visibly adds stars; stars near horizon dimmer than at zenith (screenshot).

## C. Satellites (best-in-class tracking)

### C1: Pass detail page & sky-path chart
- **Effort:** M · **Group:** G-SAT
- Tapping a pass row currently jumps to AR. Add a `PassDetailView`: polar alt-az chart (SwiftUI `Canvas`, N up) drawing the pass path with start/peak/end markers and times, rise/set azimuth compass points, peak altitude, duration, and satellite range at peak. Keep the "Find in AR" button.
- **Accept:** ISS pass renders a plausible arc (enters/exits at horizon edge, peak at correct fraction); all numbers match `Satellite.passes` output.

### C2: Pass notifications
- **Effort:** M · **Group:** G-SAT
- Local notifications 10 minutes before visible passes of user-favorited satellites (`UserNotifications`). Add a star/favorite toggle on satellite rows, persist IDs in `UserDefaults`, schedule on app foreground + after TLE refresh (cancel stale ones first, cap 20 pending). Settings toggle for the feature with permission prompt flow.
- **Accept:** with a favorited satellite and a synthetic pass 11 min away (inject via test hook), a notification is pending in `UNUserNotificationCenter`.

### C3: Satellite brightness estimate
- **Effort:** S · **Group:** G-SAT
- Estimate apparent magnitude from the standard model: `mag = stdMag − 15.75 + 2.5·log10(range² / fractionIlluminated)` with per-satellite standard magnitudes (ISS −1.8, Hubble 2.2, Tiangong 0.5, default 4.5; Starlink 5.5). Show in `Satellite.infoRows` and in pass rows; sort "brightest first" option in pass list. Return it from `Satellite.magnitude` so tap-identify weighting works.
- **Accept:** overhead ISS pass estimates between −4 and −1; unit test with fixed geometry.

## D. Product & UX

### D1: Onboarding flow
- **Effort:** M · **Files:** new `UI/OnboardingView.swift`, `AppState`, `RootView`
- Three-page first-launch flow (why camera, why location, how to calibrate: "wave phone in a figure-8, then point at the sky") with SF Symbols illustrations, requesting each permission in context. Store `hasOnboarded` in UserDefaults.
- **Accept:** shows exactly once on fresh install; permissions prompt fires from the relevant page; skippable.

### D2: WidgetKit — moon phase, tonight, next ISS pass
- **Effort:** L · **Group:** G-EXT (new widget extension target)
- Add a widget extension (this needs a new target in `project.pbxproj` — follow the existing synchronized-group pattern). Widgets: (1) small moon-phase (reuse the `MoonPhaseView` drawing logic — move it + minimal engine files into a shared framework or compile the shared sources into both targets); (2) medium "Tonight" (sunset, moonrise, best planet); (3) small "Next ISS pass" countdown. Timeline refresh 4×/day.
- **Accept:** all three widgets render in the widget gallery; moon phase matches the app.

### D3: App Intents & Siri
- **Effort:** M · **Files:** new `App/Intents.swift`
- App Intents: "When is the next ISS pass?", "What's the moon phase?", "Is <planet> visible tonight?" returning spoken/short answers from the engine, plus an OpenIntent deep-linking into an object's detail page.
- **Accept:** intents appear in Shortcuts app; each returns a correct sentence for the current location.

### D4: Observation log & favorites (SwiftData)
- **Effort:** L · **Files:** new `Core/Log/*`, detail + new `UI/LogView.swift`, `RootView` (5th tab or Catalog section)
- SwiftData model `Observation { objectID, date, notes, seeingRating, location }`. "Log observation" button on every detail page (pre-filled with current conditions: moon phase, object alt/az). Favorites: star toggle on detail pages; favorites section at top of Catalog; Messier "seen" progress ring (x/110).
- **Accept:** log entries persist across launches; progress ring updates.

### D5: Photo capture & share
- **Effort:** S · **Files:** `UI/SkyTabView.swift`, `AR/SkyRenderer.swift`
- Shutter button in the Sky HUD: `arView.snapshot(saveToHDR:)` → share sheet, with a small "AstroSky · <date> · <location>" caption overlay composited onto the image. Works in both AR and manual modes.
- **Accept:** shared image contains the camera feed + overlay + caption.

### D6: Accessibility & localization pass
- **Effort:** M · **Files:** all `UI/*` (coordinate with other G-UI tasks)
- VoiceOver labels for every HUD control and AR selection announcements ("Selected Jupiter, altitude 34 degrees, south-west"), Dynamic Type audit (no fixed-size text below `.caption2` semantics), and extract all user-facing strings into a String Catalog (`Localizable.xcstrings`) with a Spanish translation as proof.
- **Accept:** Accessibility Inspector shows no unlabeled controls; app runs fully in Spanish.

## E. Platform extensions

### E1: watchOS companion
- **Effort:** L · **Group:** G-EXT
- Watch app: moon phase + rise/set complication, "Next pass" view, and a "what's that bright dot" list (top 5 brightest objects currently up, from shared engine code).
- **Accept:** watch simulator shows correct data for the configured location.

### E2: Live Activity for satellite passes
- **Effort:** M · **Group:** G-EXT (depends on C2 landing first)
- Start a Live Activity when a favorited pass begins in < 30 min: countdown → live altitude/azimuth ("Look WSW, 40° up") during the pass → ends after. Dynamic Island support.
- **Accept:** simulated pass drives the activity through all three states.

### E3: iPad & landscape layout
- **Effort:** M · **Files:** `UI/*`, pbxproj orientations
- Enable landscape + iPad multitasking sizes: `NavigationSplitView` for Catalog on regular width, HUD controls repositioned for landscape safe areas, AR view unaffected.
- **Accept:** no clipped/overlapping HUD at iPhone landscape and iPad 2/3 split; Catalog shows sidebar+detail on iPad.

### E4: In-app 3D solar-system orrery
- **Effort:** L · **Group:** G-EXT (new `UI/OrreryView.swift` + RealityKit non-AR scene)
- A separate RealityKit `.nonAR` scene: Sun-centered orrery using `PlanetEphemeris.heliocentricPosition` with log-scaled distances, orbit rings, pinch/drag camera, date scrubber sharing `AppState.timeOffset`. Entry point from the Catalog tab.
- **Accept:** planet angular arrangement matches the AR sky's ecliptic longitudes for the same date.

## F. Engineering & infrastructure

### F1: CI on GitHub Actions
- **Effort:** S · **Files:** new `.github/workflows/ci.yml`
- macOS runner: build the app for `generic/platform=iOS Simulator` and run the test suite on an iPhone simulator, on every PR. Cache DerivedData. Add a status badge to README.
- **Accept:** workflow green on a trivial PR.

### F2: Bundle a real star catalog at build time
- **Effort:** M · **Files:** new `Scripts/fetch_hyg.swift` (or shell), README, pbxproj (run-script phase)
- Instead of asking users to hand-download the HYG CSV: a script that downloads the HYG database, strips it to `id,proper,ra,dec,dist,mag,ci,con` rows with mag ≤ 6.5 (~9k stars, ~500 KB), and writes `AstroSky/hygdata.csv`. Document the CC BY-SA attribution in Settings' About section. Keep the app working when the file is absent.
- **Accept:** fresh clone + script + build shows a dense sky; `HYGCatalogLoader` tests still pass.

### F3: Swift 6 strict concurrency
- **Effort:** M · **Files:** pbxproj (`SWIFT_VERSION = 6.0`), any files with diagnostics
- Flip the language mode to Swift 6 and fix all strict-concurrency diagnostics properly (real isolation, not `@unchecked` sprinkling — justify each remaining `@unchecked Sendable` in a comment). Watch the Timer/Combine callbacks in `SkyRenderer` and the delegate hops in `LocationService`.
- **Accept:** builds clean in Swift 6 mode; all tests pass; no new `@unchecked` without a comment.

---

## Suggested execution order

1. **P0** (alone) → merge.
2. Wave 1 (parallel): A1, B1, C1, D1, F1.
3. Wave 2 (parallel): A2, B4, C2, D5, F2.
4. Wave 3 (parallel): A3+A5 (same agent), B3, C3, D2, E3.
5. Wave 4 (parallel): A4, A6, B2, B5, D3, D4, F3.
6. Wave 5: E1, E2, E4, D6 (last — it touches everything).

Each wave stays inside the conflict-group rules; merge and rebase between waves.
