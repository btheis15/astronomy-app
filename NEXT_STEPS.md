# AstroSky — Next Steps (post-IMPROVEMENTS.md audit)

_Written 2026-07-11 after a four-way code review of commits `0217c82..5902203` (the past day's work implementing IMPROVEMENTS.md). This file is the working plan for the next sessions. Work tier by tier (T0 → T3). Every task is self-contained with file references and acceptance criteria so it can be executed independently._

## Ground rules (unchanged from IMPROVEMENTS.md)

- **Do not hand-edit `project.pbxproj`** (Xcode synchronized groups — new `.swift` files compile automatically; anything needing a project-file change is a human step).
- **Zero third-party dependencies.** First-party frameworks only.
- App target is Swift 6 strict concurrency; new code must be warning-free.
- User-facing strings auto-extract to `Localizable.xcstrings` — **every new key needs a Spanish (es) translation**.
- Preserve the design language: `.ultraThinMaterial` HUD, indigo accent, red night mode, `AstroGlyphs`.
- After each task: build, run tests, commit. Existing Meeus fixture tests must stay green.
- **Ignore widgets, Live Activities, watchOS, WeatherKit, iCloud** — those stay in `FUTURE_UPDATES.md`. This plan is the main phone app only.

## ⚠️ Build environment note (blocks `xcodebuild` from CLI right now)

The HANDOFF.md build command currently fails on this machine — **not a code problem**: the iOS 26.5 simulator runtime matching Xcode 26.6 is not installed (only iOS 27 beta runtimes are), and CLI first-launch hasn't been run. **Human steps, once:**

```bash
sudo xcodebuild -runFirstLaunch
xcodebuild -downloadPlatform iOS        # installs the iOS 26.5 simulator runtime
```

Until then, code health can be checked with a target-based device-SDK build that skips the asset catalog:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project AstroSky.xcodeproj -target AstroSky -sdk iphoneos \
  CODE_SIGNING_ALLOWED=NO EXCLUDED_SOURCE_FILE_NAMES="*.xcassets" build
```

That currently succeeds with 0 errors / 4 warnings (see T0.4). Full simulator tests (73 `@Test` functions) must be re-run once the runtime is installed.

---

# Part A — Assessment of the past day's execution

**Branch state:** all work is on `feature/p3-refactors` (1 commit ahead of `origin/main`, pushed, unmerged). Working tree clean.

## Scorecard vs IMPROVEMENTS.md

| Tier | Verdict | Detail |
|---|---|---|
| **P0 tracking (S1–S6)** | **Architecture landed; core math is wrong** | `.gravity` alignment, north-offset δ applied to `skyRoot` via `SceneEvents.Update`, circular low-pass + deadband + slew cap, VR slerp with shortest-path — all genuinely in place. **But δ has an inverted sign** (T0.2), there's **no fast initial acquisition or reset** (T0.3), the manual-align calibration lock was skipped, and `cameraDidChangeTrackingState` is an empty stub. |
| **P1 correctness/perf** | ~70% | 3 of 4 view-body ephemeris offenders fixed; async HYG load, FavoritesStore, formatter cache, dead-code deletion all done. TelescopeSection still computes optics in the body; search is still linear scan; **P1.6 (frame unification) not attempted**. |
| **P2 UI/UX** | ~75% | TonightPlanner + "Best for your telescope", Catalog IA, mode menu, moon NavigationLink, permission alerts, manual-location validation all done. Leftovers: Observe Tonight still in sidebar, `"Loading…"` literals, HUD bar can't wrap, sheets not unified. **"Replay intro" is a dead button** (T0.5). |
| **P3 architecture** | ~60% | File splits, EquipmentStore/FavoritesStore, os.Logger: solid. Dedup work (P3.3) mostly not done; magic numbers half-named; satellite-track entity still recreated. |
| **P4 features** | Small wins done | Event notifications ✅, log edit ✅ (CSV export shares a string, not a file). **P4.6 time travel was mis-deferred** — it needs no entitlement and belongs back in scope (T2.4). |
| **P5 a11y/tests/hygiene** | Partial | Glyph/canvas/chart labels ✅. **48 of 249 string-catalog keys have no Spanish**, VoiceOver announcements bypass localization, test target still Swift 5, several spec'd test suites missing. |

## Quality verdict

High throughput and the architecture is genuinely better (12,900 lines across 82 well-factored files; persistence keys verified regression-free). But three defects would have shipped:

1. **316 duplicate images (66 MB) committed and shipping in the app bundle** — commit `5902203` swept in Finder-style `* 2.jpg` copies of every object photo. Verified byte-identical to originals and never referenced by code. App bundle grew 121 MB → 190 MB.
2. **The headline P0 feature converges to the wrong azimuth** — the δ estimator's sign is inverted, and the unit tests encode the same inverted sign, so 73/73 tests pass while the sky aligns mirror-image wrong. Lesson for future sessions: tests derived from the implementation (instead of from the spec's worked formula) validate bugs.
3. **A visible Settings button does nothing** ("Replay intro") — the flag is written but nothing observes it.

Pattern to watch: several spec items were silently skipped or half-done with no note anywhere (P1.6, P3.3, the S3 align-lock, hysteresis). Future sessions should end by updating this file's checkboxes honestly — a skipped item marked "skipped because X" is fine; silence is not.

---

# Part B — Work plan

## T0 — Critical fixes (do these first, in order)

### T0.1 Delete the 316 duplicate images ✅ CRITICAL, EASY
`AstroSky/ObjectImages/` contains 316 files matching `* 2.jpg`, all byte-identical Finder duplicates of same-named originals, all added in `5902203`. They ship in the bundle (+66 MB). No code references them (`ObjectImagery.swift` loads by exact key).
```bash
cd /Users/brian/Desktop/AstroSky && find AstroSky/ObjectImages -name "* 2.jpg" -delete
```
**Accept:** `ls AstroSky/ObjectImages | grep -c " 2"` → 0; 434 files remain; build succeeds; commit. Do **not** rewrite git history to reclaim pack size without asking the user first.

### T0.2 Fix the inverted north-offset sign ✅ CRITICAL
`AstroSky/AR/NorthCalibrator.swift:86` computes `rawDelta = arkitAz − trueHeading`. Correct is **`trueHeading − arkitAz`** (matches IMPROVEMENTS.md line 37, `δ_raw = trueAz − arkitAz`). Derivation: scene north is −Z (`SkySceneBuilder.swift:62-66`); rotating −Z about +Y by φ lands it at world azimuth −φ; with camera facing ARKit +X (arkitAz = +π/2) and trueHeading = 0, the sky needs δ = −π/2, so δ = trueHeading − arkitAz.
- Flip the subtraction at `NorthCalibrator.swift:86`.
- **Fix the tests too** — `AstroSkyTests/NorthCalibratorTests.swift:68-77` (and any other convergence assertions) currently assert the inverted sign. Re-derive each expected value from the formula above; do not just negate blindly.
- Add the spec'd wraparound test: trueHeading = 359°, arkitAz = 1° must converge near −2° (short way), not +358°.
**Accept:** tests pass with the new sign; **flag for on-device outdoor verification** (point phone at a known object; overlay must match reality, not its mirror).

### T0.3 Fast initial acquisition + reset for NorthCalibrator
Today δ starts at 0 with full-weight accumulators (`NorthCalibrator.swift:46-52`) and a permanent 2°/s slew cap — the sky can be up to 180° wrong for ~90 s at launch, and `sessionInterruptionEnded` (`SkyRenderer.swift:765-774`) restarts ARKit tracking without resetting the calibrator.
- Add an `acquiring` state: until the first N (≈5) quality-gated samples arrive, snap δ directly to the circular mean (no slew, no deadband), then switch to the slow-tracking regime.
- Add `reset()` (clears accumulators + re-enters `acquiring`); call it from `sessionInterruptionEnded` and whenever the AR session is restarted (`startARSession`, error-102 recovery, mode changes back to AR).
**Accept:** unit tests: cold start converges within 5 samples; post-`reset()` re-acquires; existing slew/deadband tests still pass in tracking regime.

### T0.4 Fix the 4 Swift-6 warnings in ScaleModelTexture
`AstroSky/AR/ScaleModelTexture.swift:17,20,28,34` — "call to main actor-isolated initializer `init(image:withName:options:)` in a synchronous nonisolated context". Mark the enclosing function/type `@MainActor` (callers are already main-actor; follow the `SkySceneBuilder`/`ScaleModelBuilder` precedent from the F3 migration).
**Accept:** build 0 errors / **0 warnings**.

### T0.5 Fix the dead "Replay intro" button
`SettingsView.swift:118-120` sets `hasOnboarded = false`, but `RootView.swift:51` reads it once in a one-shot `.task`. Replace with reactive presentation, e.g. `if !appState.hasOnboarded { OnboardingView() }` or `.onChange(of: appState.hasOnboarded)` driving the sheet/fullScreenCover.
**Accept:** tapping Replay intro immediately presents onboarding without relaunch.

### T0.6 Merge to main
After T0.1–T0.5: PR `feature/p3-refactors` → `main` (repo `btheis15/astronomy-app`), summarizing the fixes. Do not merge with the duplicate images still in the branch tip.

## T1 — Finish what IMPROVEMENTS.md started (tracking first)

### T1.1 Manual-align calibration lock (spec S3, skipped)
`SkyRenderer.handleAlignPan` (`SkyRenderer.swift:724-730`) adjusts `skyAlignmentOffset` but auto-corrections keep slewing the sky out from under a hand-aligned user. Implement the spec: on manual align, fold current δ into `skyAlignmentOffset`, then suspend the calibrator (or shrink its authority ~10×); the existing reset button restores automatic mode. Consider making the persisted offset session-scoped (persist with a date; discard if >12 h old) instead of forever (`AppState.swift:135,178-180`), and stop writing UserDefaults on every gesture frame — write once on gesture end.

### T1.2 Tracking-state handling (spec S5, stubbed)
`SkyRenderer.swift:776-777` is empty. On `.limited(...)` show a small HUD hint ("Tracking limited — slow down / more light"); on sustained `.notAvailable` (~5 s) fall back to VR mode with a path back when tracking recovers. Also surface `sessionWasInterrupted` (`:761`) as a brief hint.

### T1.3 Calibrator robustness (spec S2 gaps)
In priority order: (a) **pitch gate** — skip δ samples when the camera pitch is within ~25° of zenith (both CLHeading and the horizontal projection at `NorthCalibrator.swift:79-83` are ill-conditioned there — and pointing up is this app's normal pose); (b) 2–3 s hysteresis before acting on a correction; (c) sample CLHeading at 4–10 Hz instead of consuming the same stale value at 60 Hz per frame; (d) invalid heading should show the **red** chip, not hide it (`SkyTabView.swift:111-113`, `LocationService.swift:108`).

### T1.4 VR-mode details (spec S4 gaps)
`SkyRenderer.swift`: availability check for `.xTrueNorthZVertical` with `.xMagneticNorthZVertical` + declination fallback (silent frozen camera today if unavailable); framerate-independent `alpha = 1 − exp(−dt/τ)` instead of hard-coded 0.107 (`:700`); seed `filteredVROrientation` from the first sample instead of identity (`:91`) to kill the swing-in; fix the stale comment at `:665`. Verify on device that VR and AR modes face the same direction (VR uses +Z screen-normal at `:684`, AR uses −Z back-camera — possible 180° inversion).

### T1.5 Remaining view-body compute (P1.1's 4th offender)
`TelescopeSection.swift:155-156` (per-eyepiece `TelescopeMath.result` + `TelescopeVisibility.assess` inside `ForEach`), `:33,54`, and `TonightPlacementCalculator.compute` at `:191` — memoize in `@State` via `.task(id:)` keyed on (object id, telescope id, eyepiece list hash), following the `ObjectDetailView.swift:84-106` pattern.

### T1.6 Catalog loading loose ends
(a) Construct `SkyCatalog(deepStars:)` **inside** the detached task, not on MainActor (`AppState.swift:283` — merging/sorting 16k stars on main). (b) When `catalog` is swapped, notify `SkyRenderer` to rebuild the star field **and labels** (today `rebuildStarField` only triggers on magnitude changes, `SkyRenderer.swift:326-329,399-404` — deep stars would silently never render in AR). (c) Index `SkyCatalog.search` (`SkyCatalog.swift:80-86`) — precomputed lowercase name/alias prefix map, fall back to contains-scan for mid-string matches.

### T1.7 PassDetailView resilience
`PassDetailView.swift:79`: if TLEs aren't loaded, the `.task` guard returns and the view shows "—" forever. Add the spec'd `ContentUnavailableView` for the empty case and re-run the task when the satellite becomes available (key the task on TLE-cache state or retry with a short delay).

### T1.8 P2 leftovers (one small task each)
- Remove "Observe Tonight" from the Catalog Tools section (`CatalogView.swift:62-63`) — Tonight's "See all" is now the entry.
- Replace literal `"Loading…"` sun/twilight rows with `ProgressView`/redacted rows (`TonightView.swift:149-150`).
- HUD top bar wrap at accessibility sizes (`SkyTabView.swift:107-177`) — `ViewThatFits` two-row fallback (spec P2.8).
- Replace `planetInfos` 4-tuple with a named struct from TonightPlanner (`TonightView.swift:21`); move `deduplicated` (`:356`) and twilight/moon assembly into the planner (finishes P2.1).
- Unify `AddTelescopeSheet`/`AddEyepieceSheet` scaffolding (`EquipmentEditorView.swift:107-216`).
- Delete dead `cycleSkyMode()`/`nextModeIcon`/`nextModeLabel` (`SkyTabView.swift:27-34,180-194`).

### T1.9 Localization + a11y debt
- Add Spanish for the **48 untranslated keys** in `Localizable.xcstrings` (list: run a script over the JSON — keys where `localizations.es` is absent; includes "Best for your telescope", "Replay intro", "Continue Anyway", "Calibrate Compass", onboarding alert bodies, "See all %lld targets"…).
- Route interpolated VoiceOver strings through `String(localized:)` format strings: the selection announcement (`SkyTabView.swift:61`), guide-arrow text.

### T1.10 Tests + project hygiene
- Bump the **test target** to `SWIFT_VERSION = 6.0` (human step in Xcode if pbxproj edit is required — it is: `project.pbxproj:400,419`).
- Add the missing spec'd suites, most valuable first: **TonightPlanner** (ranking, no-equipment behavior — see T2.2), **AR frame math** (`skyOrientation`/`sceneDirection`, pure functions — would have caught T0.2), AppState persistence/migration, FavoritesStore, TLE cache round-trip, EventsEngine conjunction/eclipse severity.
- `EquipmentStore.swift:14`: logger category "ephemeris" → "persistence".
- Name the stragglers: literal `17280` in `ObjectDetailView.swift:31`, `CatalogRow.swift:13`, `ConstellationViews.swift:26,66`; `86_400` in `OrreryView.swift:33`.
- P3.3 dedup remnants (low priority): `planetTextureKey` (keep `ObjectImagery`'s), Bortle→limiting-magnitude (keep `TelescopeOptics`'), `SkySceneBuilder` colors → `AstroPalette`.

## T2 — UX upgrades (from the fresh walkthrough; main app only)

### T2.1 Tonight tab: verdict first
The first screenful is 8 event rows + 5 twilight rows before anything actionable (`TonightView.swift:107-155`). Add a **summary card** at the top: dark window ("Dark 21:40 – 04:15"), moon interference (phase %, sets 01:30), tonight's #1 target, and — once T2.4 lands — next visible pass countdown. Collapse twilight detail to one "Dark from → until" row with the full table behind a tap/disclosure. All data already exists in TonightPlanner/RiseSet.

### T2.2 Honest "Best for your telescope"
`TonightPlanner.swift:51-53` treats **no telescope** as "everything visible", so a fresh install gets a confident recommendation list and the equipment-setup prompt (`TonightView.swift:227-231`) is unreachable. When `activeOptics == nil`, return a distinct "no equipment" result; TonightView shows a "Set up your telescope" row (mirror `ObserveTonightView.swift:19-25`) and retitles the section "Highlights tonight" with naked-eye-appropriate picks. Add the TonightPlanner unit test alongside.

### T2.3 Search everywhere, with a details path
Search only exists behind the Sky-tab magnifier, and tapping any result force-switches to AR (`SearchView.swift:66-70`; `SkyTabView.swift:171`). (a) Add `.searchable` at the Catalog root (`CatalogView.swift`) over the whole catalog via `SkyCatalog.search` (indexed per T1.6c). (b) In search results, tapping a row opens `ObjectDetailView`; "Find in AR" becomes a swipe action / trailing button. Detail pages already have Find-in-AR, so no capability is lost.

### T2.4 Time travel done right (was P4.6, wrongly deferred — pure SwiftUI)
(a) **Bug first:** clamp `AppState.timeOffset` mutations (`AppState.swift:148`, jump buttons at `TimeControlBar.swift:41-44`) — today "+1d" three times pegs the slider at +12 h while the sky sits at +3 d with no indication. (b) Then the feature: date button in `TimeControlBar` → compact `DatePicker` sheet for any date/time, ±12 h slider stays for fine scrub. (c) Hide TLE satellites with an explanatory note when |offset| > 2 days (SGP4 accuracy); orrery limited to ±100 years. Es translations for all new strings.

### T2.5 Pass urgency
Pass rows show absolute times only (`TonightView.swift:306-332`). Add a relative caption on the next upcoming pass ("in 38 min", `Text(.relative)` or `RelativeDateTimeFormatter`), and group headers "Tonight" / "Tomorrow morning". Consider a subtle highlight when a pass starts within 15 min.

### T2.6 Object detail: verdict above the fold
Order today: photo → header → RA/Dec → rise/set → chart → physical data → telescope verdict ~4 screens down (`ObjectDetailView.swift:39-57`; verdict lives at `TelescopeSection.swift:84-97,190-205`). Hoist a compact chip row into the header: visibility verdict ("Easy in your 8-inch"), best-time ("Best ~22:30"), and current alt/az. Full TelescopeSection stays where it is; raw RA/Dec moves down into the data section.

### T2.7 CSV export as a real file
`LogView.swift:75-84` `ShareLink`s a `String` — recipients get pasted text. Export a `.csv` file: a small `Transferable` struct with `FileRepresentation` (UTType `.commaSeparatedText`) writing to a temp URL named `AstroSky-log-YYYY-MM-DD.csv`.

### T2.8 Onboarding permission race
`OnboardingView.swift:53-63` sleeps 500 ms then reads authorization — on first ask the system dialog is still up (`.notDetermined`), so the pager advances behind the dialog and real denials are never caught. Observe the authorization callback (LocationService delegate / `AVCaptureDevice.requestAccess` continuation) and advance only when a determined status arrives.

## T3 — New enhancements (after T0–T2; pick in this order)

1. **Align-on-star** (spec S3 stretch, now more valuable post-T1.1): with a bright object selected, an "Align here" button on the object card computes δ so the object sits exactly where the user centered it — one tap beats two-finger dragging. Reuses the lock semantics from T1.1.
2. **Observing session list**: "Add to tonight" on object detail + Tonight's target rows → a checkable queue on the Tonight tab; checking an item off pre-fills a new observation-log entry (object, time, seeing). Pure SwiftUI + existing SwiftData log. This turns the app from lookup into a workflow: plan → find (AR guide) → log.
3. **"Visible now" filter** in catalog lists (`ObjectListView.swift`): toggle to show only objects above 10° altitude right now, sorted by altitude — the batch position computation from P1.1 already provides the data.
4. **Event detail pages**: Tonight's event rows are display-only; meteor showers deserve a small detail view (radiant chart via existing AR-radiant data, ZHR, moon interference at peak, "Find radiant in AR"), conjunctions a two-object comparison. `EventsEngine` already computes everything.
5. **Night-mode audit**: verify every sheet/alert added in the past day (calibration sheet, onboarding alerts, edit-observation sheet, DatePicker sheet from T2.4) respects the red night-vision tint — new surfaces are the classic leak.
6. **App Store readiness** (human steps, tracked in FUTURE_UPDATES.md P5.3): real bundle id, team, version bump, PrivacyInfo verification in the built .app.

## Suggested session sizing for small models

- One T0/T1 numbered item per session, max two if trivial (T0.1 + T0.4 pair well).
- Always: read the referenced files first, implement, build (see environment note), run tests when the sim runtime is available, update the relevant checkbox here with DONE/SKIPPED+reason, commit with the task id in the message (e.g. `T1.3a pitch gate`).
- Anything requiring Xcode UI (test-target Swift version, signing, new capabilities) → write the exact steps into a "HUMAN STEPS" note at the top of your commit/PR message and stop; don't attempt pbxproj edits.
- On-device outdoor verification is required for T0.2/T0.3/T1.1/T1.4 sign-offs — mark them "needs device check" until the user confirms.
