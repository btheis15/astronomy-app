# AstroSky — Improvement Instructions

Instructions for the implementing agent. Work tier by tier (P0 → P5). P0 is the headline: make the Sky tab track like SkyView / Sky Guide — stable compass, locked-in gyro, zero wobble.

## Ground rules

- **Do not hand-edit `project.pbxproj`** (Xcode synchronized groups — new `.swift` files in existing folders compile automatically).
- **Zero third-party dependencies.** Everything below uses first-party frameworks only: **ARKit** (`.gravity` world tracking), **RealityKit** (rendering), **CoreMotion** (`CMDeviceMotion`, `.xTrueNorthZVertical`), **CoreLocation** (`CLHeading`, calibration prompt), **simd** (`simd_quatf`, `simd_slerp`).
- App target is Swift 6 strict concurrency; new code must be warning-free.
- User-facing strings auto-extract to `Localizable.xcstrings` (en + es) — add Spanish translations for new keys.
- Preserve the design language: `.ultraThinMaterial` HUD, indigo accent, red night mode, `AstroGlyphs` icons.
- After each task: build, run tests, update `HANDOFF.md`.
- The existing Meeus fixture tests in `AstroSkyTests/` must stay green throughout.

---

## P0 — Sky tab: professional tracking stability (THE priority)

### Why it jumps and wobbles today (verified in code)

- **AR mode:** `SkyRenderer.swift:151` runs `worldAlignment = .gravityAndHeading`. ARKit seeds and *continuously re-corrects* world yaw from the magnetometer; every correction rotates the whole world → the sky visibly swings/jumps in azimuth. The magnetometer's errors become uncontrollable yaw motion. The sky itself is parented to a fixed identity world anchor (`SkyRenderer.swift:46`), so all perceived stability rides on ARKit's alignment choice.
- **VR mode:** `SkyRenderer.swift:653-698` assigns raw 60 Hz `CMDeviceMotion` attitude (`.xMagneticNorthZVertical`) directly to the camera — no slerp, no low-pass, no deadband → magnetometer noise and gyro jitter render 1:1 as wobble.
- **No safety net:** the only `ARSessionDelegate` method is `didFailWithError` (error-102 → one-way VR fallback, `SkyRenderer.swift:744-756`). No tracking-state observation, no interruption handling, no recovery back to AR.
- **Compass is display-only:** `LocationService.swift:98-104` keeps `CLHeading.headingAccuracy` for the HUD chip but discards the heading itself. No figure-8 calibration prompt. The two-finger align offset (`AppState.skyAlignmentOffset`) is not persisted across launches.

### S1 — Move the compass OUT of the tracking loop (the core fix)

New architecture (this is what Sky Guide-class apps ship):

1. In `SkyRenderer.startARSession()` change `configuration.worldAlignment` from `.gravityAndHeading` to **`.gravity`** (`SkyRenderer.swift:151`). Yaw becomes arbitrary but perfectly stable — pure visual-inertial odometry, no magnetometer in the loop, nothing ever snaps.
2. Introduce a **north offset δ** (radians): the yaw rotation that maps ARKit's arbitrary world frame to true north. Apply it where the manual alignment offset is already applied (`SkyRenderer.tick()`, `SkyRenderer.swift:302-303`):
   `skyRoot.orientation = simd_quatf(angle: δ + skyAlignmentOffset, axis: [0,1,0]) * baseOrientation`
   The sky content rotates; the camera is never touched. Per-frame cost: zero.
3. Estimate δ by comparing, at the same instant:
   - ARKit camera azimuth: `let f = -simd_make_float3(frame.camera.transform.columns.2); let arkitAz = atan2(f.x, -f.z)`
   - True-north device azimuth from CoreMotion (S2).
   `δ_raw = trueAz − arkitAz`, normalized to (−π, π].

### S2 — Filtered north-offset estimator (new file `AR/NorthCalibrator.swift`)

A `@MainActor` class owning the absolute-azimuth reference and all filtering. This is where the "no jumble" guarantee lives:

- **Source:** `CMMotionManager.startDeviceMotionUpdates(using: .xTrueNorthZVertical, ...)` at **4–10 Hz** (not 60 — it's a slow reference, and 10 Hz is the compass-display best practice). Check `CMMotionManager.availableAttitudeReferenceFrames().contains(.xTrueNorthZVertical)`; fall back to `.xMagneticNorthZVertical` + declination from `CLHeading.trueHeading − magneticHeading`. Derive the device-pointing azimuth by rotating camera-forward by `attitude.quaternion` and taking `atan2(east, north)` — do NOT use Euler `attitude.yaw` (gimbal trouble when the phone points near the zenith, which is the normal pose for this app).
- **Circular low-pass** — never average degrees across 0/360; filter in sin/cos space:
  `sinAcc = (1-k)·sinAcc + k·sin(θ); cosAcc = (1-k)·cosAcc + k·cos(θ); δ_target = atan2(sinAcc, cosAcc)` with small k (≈0.05 per sample — Google Sky Map smooths the magnetometer ~100× harder than the accelerometer; heading should converge slowly).
- **Quality gating:** skip samples when `CLHeading.headingAccuracy` is negative (invalid) or > 25–30°; optionally weight k ∝ 1/accuracy.
- **Deadband + hysteresis:** ignore |δ_target − δ| < 1°; require a larger correction to persist ~2–3 s (circular mean of recent samples) before acting — rejects transient magnetic disturbance (car roofs, phone cases).
- **Rate-limited application — never snap:** slew δ toward δ_target at ≤ 1–2°/s, and preferentially while the user is panning fast (`CMDeviceMotion.rotationRate` above threshold) when a small yaw shift is imperceptible; freeze corrections when the view is nearly still or a search target is centered.
- **Optional nonlinearity (Google Sky Map's shipped trick):** `correction = k · diff · |diff|^2` — tiny errors move very slowly (kills jitter), big errors converge fast (kills lag).
- Unit-test the estimator: wraparound at 0/360, deadband, gating on bad accuracy, slew-rate cap (pure math — very testable).

### S3 — Calibration UX (make the user's compass trustworthy)

- **Figure-8 system prompt:** implement `locationManagerShouldDisplayHeadingCalibration(_:)` in `LocationService` returning `true` when the Sky tab is active and no gesture is in progress — iOS shows its calibration panel. (Requires `startUpdatingHeading()`, already running.)
- **Re-tier the accuracy chip** (`SkyTabView.swift:189`) to realistic device values (iPhones commonly report 20–25°, rarely <10°): `<10°` green "excellent", `10–25°` yellow "OK", `>25°` / invalid red "needs calibration" — and make the red chip **tappable**, showing a short sheet: figure-8 instructions + "move away from magnets/metal, remove magnetic case" + a button to fine-align manually.
- **Manual align = calibration lock (Sky Guide's model):** keep the existing two-finger drag (`SkyRenderer.swift:720-726`), but when the user sets it: (a) fold the current δ into `skyAlignmentOffset` and **suspend automatic corrections** (or shrink their authority ~10×) so the sky never moves out from under a user who has aligned it by hand; (b) **persist** the combined offset in UserDefaults per session-day (currently `AppState.swift:243` resets every launch); (c) the existing reset button restores automatic mode.
- **Align-on-star (stretch, small):** with a bright object selected, add "Align here" to the object card — computes the exact δ so the tapped star sits where the user centered it. This is the AstroHopper/telescope-style one-tap alignment and beats dragging.

### S4 — VR mode: smooth and true

`SkyRenderer.swift:653-698`:
- Switch the reference frame from `.xMagneticNorthZVertical` to **`.xTrueNorthZVertical`** (declination handled by the system) with the availability check + fallback above.
- **Quaternion slerp low-pass** on the camera: keep `filtered` state; per sample `filtered = simd_normalize(simd_slerp(filtered, target, alpha))` with framerate-independent `alpha = 1 − exp(−dt/τ)`, τ ≈ 0.15 s. Enforce shortest path (`if simd_dot(filtered.vector, target.vector) < 0 { target = -target }`). This kills the wobble while keeping latency imperceptible.
- Drive the update from the motion callback as today, but consider `SceneEvents.Update` pull (read latest sample per render frame) so updates can't beat against the display refresh.

### S5 — Session lifecycle & tracking-state handling (`SkyRenderer.swift`)

- Implement `session(_:cameraDidChangeTrackingState:)`: on `.limited(.excessiveMotion/.insufficientFeatures/.initializing)` show a small HUD hint ("Tracking limited — slow down / more light") instead of letting the sky drift silently; on `.notAvailable` for a sustained period, fall back to VR mode.
- Implement `sessionWasInterrupted`/`sessionInterruptionEnded` + `sessionShouldAttemptRelocalization` → return `false` (a sky app has no persistent world content worth relocalizing; a fresh `.gravity` frame + re-estimated δ is cleaner than ARKit trying to restore an old origin and yawing the world). On interruption end, re-run the session with `.resetTracking` and let `NorthCalibrator` re-converge.
- Error-102 fallback: with `.gravity` alignment the compass is no longer required by ARKit, so error 102 should become rare — keep the VR fallback but add a path back: when AR becomes available again (tracking normal), offer "Switch back to AR" in the HUD rather than the current one-way, full-rebuild `.id(effectiveMode)` teardown.

### S6 — Rendering cadence hygiene (perceived stability)

- Keep the good architecture: sky in a world-anchored graph, camera moved by ARKit — per-frame sky work is already zero. Verify nothing heavy runs on the frame path: `updateGuideIfNeeded` (0.1 s throttle) is fine; keep it that way.
- The 0.5 s `tick()` `Timer` is fine for sidereal rotation (imperceptible per step) but must not be the path that applies δ slewing — apply δ changes via `SceneEvents.Update` so motion is phase-locked to the renderer, not a `RunLoop` timer that can beat against refresh. While there, make `tick()` diff settings instead of re-applying ~10 `isEnabled`/opacity values every tick.
- Main-thread hitches read as tracking wobble: audit that no catalog/ephemeris math runs inside frame callbacks (see P1.1 for the view-body offenders).
- Free-look/orrery (`.nonAR` camera) can exploit ProMotion 120 Hz; AR camera feed is 60 fps — no work needed there.

### P0 acceptance criteria

- Pan the phone across the sky and hold still: overlay does not drift, swim, or step; no visible azimuth correction ever appears as motion (corrections happen sub-degree, slow, or during fast pans).
- Cover the magnetometer with a magnet briefly: the sky must NOT jump; the chip may go red and prompt calibration.
- VR mode held still shows no visible jitter; motion tracks with no perceptible lag.
- Two-finger align, lock, kill app, relaunch same evening: alignment preserved.
- All existing tests green; new `NorthCalibrator` unit tests pass.

---

## P1 — Correctness & performance fixes

### P1.1 Stop running ephemeris math in view bodies
The correct pattern exists — `AltitudeChartSection` (`UI/ObjectDetailView.swift`) caches via `.task(id:)`. Apply it to the four offenders:
- `ObjectDetailView.riseSetSection` — full rise/set bisection in the body → compute in `.task(id: object.id)` into `@State`.
- `PassDetailView.samples` — ~80 SGP4 steps per body evaluation (plus `compass(at:)`/`rangeAtPeakKm` re-deriving) → compute once in `.task`, store in `@State`; add `ContentUnavailableView` when empty.
- `CatalogRow` + `ConstellationListView`/`ConstellationDetailView` (`UI/CatalogView.swift`) — per-row `horizontal(...)`/`precessFromJ2000` solves → batch-compute per list load in `.task(id:)` with a 60 s refresh; pass plain values to rows.
- `TelescopeSection.eyepieceTable` — recomputes `TelescopeMath.result` + `TelescopeVisibility.assess` per eyepiece per redraw → memoize in `@State` keyed on (object, telescope, eyepieces).

### P1.2 Catalog construction off the launch path
`SkyCatalog()` builds synchronously in `AppState.init` (`App/AppState.swift:24`), including the optional 16k-star HYG CSV parse. New way: cheap default catalog at init; HYG parse (if bundled) in a detached `.utility` task publishing through an `@Observable` property. Before HYG ever ships: index `SkyCatalog.search` (lowercase-name prefix index, not linear `localizedCaseInsensitiveContains`) and keep `SkyRenderer.identifyObject` limited to rendered objects.

### P1.3 AppState persistence pathologies (`App/AppState.swift`)
- Favorites getters re-read + re-parse UserDefaults and rebuild a `Set` on every access (`:207-217`), `favoriteObjects` adds N catalog lookups → load once into in-memory `@Observable` sets; write defaults only on mutation.
- The ~15 `didSet { UserDefaults }` settings all fire during `init` reassignment → property wrapper or direct backing-storage init that skips `didSet`.
- `bortleClass.didSet` reassigns itself to clamp (reentrant) → clamp at the write site.

### P1.4 `AstroFormat.timeFormatter` (`Core/Astronomy/Formatting.swift`) — shared mutable static `DateFormatter`, timezone mutated per call, no isolation → make `AstroFormat` `@MainActor` or cache formatters per time-zone identifier.

### P1.5 Delete dead code
- `SkyRenderer.loadDeepSkySprites()` + `SkySceneBuilder.makeDeepSkySprite` (unreachable since sprite removal `24092ae`).
- `AstroTime.deltaT`/`julianEphemerisDate` — never called: either wire ΔT into the ephemeris entry points (preferred; facility already exists) or delete.
- `OrreryView`: the tautological `where planet != .earth || true`.

### P1.6 Unify apparent-place frame conventions (`Core/Astronomy/`)
Sun/Moon compute of-date apparent then de-precess to J2000 (duplicated in `SunObject`/`MoonObject`); planets bake nutation into a nominally-J2000 vector with J2000 mean obliquity (`Planets.swift:204-212`) that callers precess again. New way: one documented helper — `apparentEquatorialOfDate(...)` + shared `deprecessToJ2000(...)` — used by Sun, Moon, planets, minor bodies. Meeus fixture tests must stay green.

---

## P2 — UI/UX & layout restructure

### P2.1 Consolidate the three "tonight" experiences
Tonight tab, Observe Tonight (buried in Catalog), and TelescopeSection's tonight block each independently compute "what's well-placed tonight."
- Create `Core/Planning/TonightPlanner.swift`: twilight, moon summary, planet visibility, pass dedup (move `deduplicated(...)` out of `TonightView`), telescope-aware target ranking (from `ObserveTonightView.load()`).
- Tonight tab becomes the single planning surface: add a "Best for your telescope" section (top ~5 + "See all" `NavigationLink` to the full list, which keeps `ObserveTonightView`'s excellent empty/loading states).
- Remove "Observe Tonight · your telescope" from the Catalog sidebar.
- Replace `TonightView.planetInfos`' 4-tuple with a named struct from the planner.

### P2.2 Catalog information architecture (`UI/CatalogView.swift`)
Sidebar section headers: **Catalogs** (Solar System, Stars, Messier, Caldwell, NGC, Constellations), **Satellites**, **Tools** (Observing Log, Orrery). Shorten "Solar System Orrery" → "Orrery". Add an Observing Log toolbar entry (book icon) on the Tonight tab.

### P2.3 One control for sky view mode
HUD cycle button shows the *next* mode's icon; Settings has a duplicate picker. New way: HUD button becomes a `Menu` (same 40×40 capsule) labeled with the **current** mode's icon, listing AR / VR / Free-look with checkmarks. Settings picker stays (same binding).

### P2.4 Standardize loading/empty/error states
Gold standard is `ObserveTonightView`/`LogView` (ProgressView + `ContentUnavailableView`). Fix: `SearchView` (blank on no results → `ContentUnavailableView.search(text:)`), `TonightView` (inline `"Loading…"` literals → `ProgressView`; events section silently absent while scanning → placeholder row), `ExploreTabView` (ARKit unavailable → explanatory `ContentUnavailableView`), `OrreryView` (brief loading state).

### P2.5 TonightView row consistency — the Moon row is a bare `onTapGesture` with no affordance while planets/passes are `NavigationLink`s → make it a `NavigationLink` to the Moon's `ObjectDetailView`.

### P2.6 Onboarding permission handling (`UI/OnboardingView.swift`) — denied permissions currently advance silently → inline "You can enable this later in Settings" + `Link(UIApplication.openSettingsURLString)`; add "Replay intro" in Settings → About (resets `hasOnboarded`).

### P2.7 Settings manual location — invalid lat/long "Set" fails silently → validate and show a red footer message.

### P2.8 Dynamic Type / fixed widths — remove `.frame(width: 190)` on Explore's scale picker; drop `fixedSize` on `SkyTabView.locationBadge` or use `ViewThatFits`; let the 6-control HUD top bar wrap at accessibility sizes.

### P2.9 Shared components — create `UI/Components/DetailRow.swift` replacing the `row(label:value:)` helper copied verbatim in `ObjectDetailView`, `TonightView`, `PassDetailView`; unify the near-identical `AddTelescopeSheet`/`AddEyepieceSheet` around one preset+fields+toolbar scaffold.

---

## P3 — Code architecture cleanup

### P3.1 Split oversized multi-type files (no behavior change)
- `UI/SkyTabView.swift` → move `CapturedPhoto`, `ShareSheet`, `GuideArrowView`, `TimeControlBar`, `ObjectCardView` to `UI/Sky/`.
- `UI/CatalogView.swift` → split `ObjectListView`, `CatalogRow`, `ConstellationListView`, `ConstellationDetailView` into `UI/Catalog/`.
- `UI/EyepiecePreviewView.swift` (438 lines — a rendering engine in the UI folder) → draw functions + `SeededRNG` + FNV hash to `UI/Rendering/EyepieceSimulation.swift`.
- `UI/OrreryView.swift` → `OrreryScene` (RealityKit coordinator) to `AR/OrreryScene.swift`; source `semiMajorAU` from `Core/Astronomy/Planets.swift` elements instead of a duplicate hardcoded table.

### P3.2 Slim AppState into stores
- `EquipmentStore` — move CRUD mutations + JSON persistence out of AppState (model file already exists).
- `FavoritesStore` — one API for object + satellite favorites (`toggleFavorite(id:kind:)`), in-memory sets per P1.3, persistence keys unchanged.

### P3.3 Deduplicate core logic
`planetTextureKey` (SkySceneBuilder + ObjectImagery → keep ObjectImagery's); heliocentric rotation + phase-angle blocks (Planets + MinorBodies → AstroMath); Bortle→limiting-magnitude (AppState + TelescopeOptics → keep optics); `solarSystemObjects` assembly (CatalogView + ObserveTonightView → one `SkyCatalog` helper; largely absorbed by P2.1); make `SkySceneBuilder.planetColor`/`deepSkyColor` read from `AstroPalette` so the UI and AR palettes can't drift.

### P3.4 Name the magic numbers — `43_200`/`86_400` time-travel bounds, 300 s scrub step, HUD size 40, `prefix(8)`, `positionKey`'s 17280. Canvas-art coefficients may stay literal.

### P3.5 Lightweight logging — failures are uniformly silenced with `try?` (TLE fetch, location, propagation). Keep graceful degradation; add `os.Logger` categories (`network`, `ephemeris`, `ar`) at `.error`/`.notice` so field issues are diagnosable in Console.

### P3.6 AR renderer tidy-up — `updateSatelliteTrack` destroys/recreates the track `Entity` each refresh → reuse entity, swap mesh; replace `nonisolated(unsafe) guideTaskPending` with a `@MainActor` property. (Settings diffing covered in S6.)

---

## P4 — Features (in value order)

### P4.1 Sky-event notifications (small — data exists)
`EventsEngine.upcoming` already finds conjunctions, eclipses, meteor peaks; only passes notify. Add `EventNotificationScheduler` on the `PassNotifications` pattern; opt-in Settings toggle; `UNCalendarNotificationTrigger` the evening before each event.

### P4.2 Observing-log export + editing (small)
`ShareLink` in `LogView` toolbar exporting CSV via `Transferable`/`FileRepresentation`. Make log rows tappable → detail/edit sheet (currently delete-only).

### P4.3 Weather-aware observing forecast (medium — biggest gap vs competitors)
Adopt **WeatherKit** (first-party; needs the capability + entitlement — human step in Xcode). "Conditions" section atop the Tonight tab: cloud-cover %, hourly clear-sky strip for the night, go/no-go verdict feeding `TonightPlanner` rankings. Hide the section gracefully when entitlement/network is unavailable.

### P4.4 WidgetKit widgets (medium — human step: create the widget-extension target in Xcode first; stop if absent)
Moon phase, "Tonight at a glance," next-ISS-pass widgets; App Group (`group.…AstroSky`) for shared data — move relevant UserDefaults reads behind a shared suite; reuse `MoonPhaseView` drawing + `AstroGlyphs`.

### P4.5 iCloud sync (medium — human step: iCloud capability/entitlements)
SwiftData + CloudKit for `ObservationLogEntry` (CloudKit-compatible fields); `NSUbiquitousKeyValueStore` mirroring for favorites + equipment JSON.

### P4.6 Full planetarium time travel (medium)
Sky view limited to ±12 h today. Add a date button to `TimeControlBar` → compact `DatePicker` sheet for any date/time, keeping the ±12 h slider for fine scrub. Hide TLE satellites (with a note) beyond |offset| ≈ 2 days (SGP4 accuracy decays).

### P4.7 Later (needs targets, human step): Live Activities for passes; watchOS companion.

---

## P5 — Accessibility, tests, hygiene

### P5.1 Accessibility
- `accessibilityLabel`s on `ObjectGlyph`/`AstroGlyphs` (often the only type indicator), the `EyepiecePreviewView` canvas ("Simulated eyepiece view of M42…"), and `PassSkyChart` (summarize: rises NW, peaks 62°, sets SE). Exemplars already in-repo: `LogView` seeing stars, `MoonPhaseView`.
- Localize interpolated VoiceOver sentences (SkyTab selection announcement, guide-arrow text) via `String(localized:)` format strings.

### P5.2 Tests (add alongside each area you touch)
`NorthCalibrator` (P0); AppState persistence + `preferManualSky`→`skyDisplayMode` migration; `FavoritesStore`; `SatelliteService` TLE cache round-trip; `EventsEngine` conjunction closest-approach + eclipse severity; AR frame math (`skyOrientation`/`sceneDirection` NWU→RealityKit — pure functions); `SkyCatalog.search` ranking; `TonightPlanner`. Bump the test target to Swift 6 (app is 6.0, tests are 5.0).

### P5.3 Project hygiene (some human steps)
- Bundle id is placeholder `com.example.AstroSky` (human: Xcode Signing); normalize `DEVELOPMENT_TEAM` across configs; bump `MARKETING_VERSION`.
- Verify `PrivacyInfo.xcprivacy` actually ships in the built .app (not referenced by name in pbxproj; synchronized groups likely include it — check) and audit required-reason/network declarations.
- Delete the stray "Untitled Project" widget/watch stubs flagged in HANDOFF.md; decide the fate of the untracked `Force_Pull_Pinch_Twist_AR_Interactions.md` (commit under `docs/ideas/` or leave deliberately untracked).

---

## Frameworks & techniques summary (P0 answer to "what do I need?")

| Need | Use | NOT needed |
|---|---|---|
| Smooth motion tracking | ARKit `ARWorldTrackingConfiguration` with `.gravity` (VIO) | `.gravityAndHeading`, third-party AR |
| Absolute north reference | CoreMotion `CMDeviceMotion` @ `.xTrueNorthZVertical`, 4–10 Hz | Raw `CLHeading` driving the view |
| Compass quality + calibration | CoreLocation `CLHeading.headingAccuracy`, `locationManagerShouldDisplayHeadingCalibration` | — |
| Smoothing math | simd: `simd_slerp` low-pass (τ≈0.15 s), circular sin/cos heading filter, deadband + hysteresis + slew-rate cap, swing-twist yaw extraction | Full Kalman/EKF (ARKit's VIO already is one), any DSP package |
| Rendering | RealityKit, `SceneEvents.Update` for orientation application | SceneKit (maintenance mode), custom Metal (catalog is small) |
| Reference implementations to read (not import) | Google Sky Map `stardroid` sensor design doc + damping constants (Apache-2.0), Sky Guide support docs (drag-to-align UX), NASA MarsImagesIOS (`.xTrueNorthZVertical` usage) | Any runtime dependency |

## Suggested execution order

1. **P0 (S1→S6)** — the stability epic; verify against the acceptance criteria on a real device outdoors.
2. P1 (perf/correctness, invisible changes, tests stay green)
3. P2.1 + P2.2 (IA restructure), then P2.3–P2.9 (screen polish)
4. P3 refactors (safest after IA settles)
5. P4.1 + P4.2 (small wins) → P4.3 → target-dependent P4.4–P4.7
6. P5 continuously — add tests with each area touched
