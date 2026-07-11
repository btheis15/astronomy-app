# AstroSky — Build Handoff

_Handoff for continuing work in a new Claude session opened on the AstroSky project._

## What this project is
**AstroSky** is a native iOS AR astronomy app (SwiftUI + ARKit/RealityKit + Swift Charts, `@Observable`, no third-party deps). Point the phone at the sky to see stars, planets, constellations, Messier/Caldwell/NGC objects and live satellites; plus a Telescope Guide and an AR scale-model explorer.

## Where everything lives (IMPORTANT)
- **The real app + all work:** `/Users/brian/Desktop/AstroSky/` → open `AstroSky.xcodeproj`.
- **GitHub:** `btheis15/astronomy-app`. Work branch `feature/world-class-roadmap`, merged into `main`. Everything below is committed & pushed.
- ⚠️ **"Untitled Project"** (a separate scratch project) is NOT the app. Widget/watch target stubs were accidentally created there — delete them. Recreate targets inside **AstroSky.xcodeproj**.

## How to build / test (no Xcode UI needed)
```bash
cd /Users/brian/Desktop/AstroSky
# Build
xcodebuild -project AstroSky.xcodeproj -scheme AstroSky -destination 'platform=iOS Simulator,name=iPhone 17' build
# Test (Swift Testing suite)
xcodebuild -project AstroSky.xcodeproj -scheme AstroSky -destination 'platform=iOS Simulator,name=iPhone 17' test
```
- Targets iOS 26. New `.swift` files are auto-compiled (Xcode synchronized groups) — no need to add to the project.
- **Do NOT hand-edit `project.pbxproj`** (crashes Xcode while open). Anything needing a project-file change must be done in Xcode's UI (see "Remaining").
- Bundle id `com.example.AstroSky`; signing unset (Simulator only). Camera + location usage strings already set.

## Working rhythm that's been used
Per task: implement → `xcodebuild build` (must be 0 errors/0 warnings) → run tests if engine/logic touched → screenshot via `simctl` for visual features → `git commit` + `git push` (standing permission to commit/push/merge as save-points). Merge `feature/world-class-roadmap` → `main` at milestones.

## DONE — built, tested, committed, on `main`
Roadmap (from `ROADMAP.md`):
- **P0** first-build fixes (added `import simd`; migrated `CLGeocoder`→`MKReverseGeocodingRequest`)
- **A1** glowing star sprites · **A2** Milky Way band · **A3** grid/ecliptic/equator overlays · **A4** satellite trails · **A5** compass accuracy chip + two-finger fine-align · **A6** FOV label decluttering
- **B1** nutation + aberration + light-time (Venus ≤0.05°) · **B2** Ceres/Vesta/Pallas (Keplerian) · **B3** events engine (conjunctions/eclipses/meteor showers + AR radiants) · **B4** Caldwell (109) + NGC catalog, all 88 constellations · **B5** Bortle picker + horizon light-pollution glow
- **C1** pass detail polar chart · **C2** pass notifications (favorites) · **C3** satellite brightness estimate
- **D1** onboarding · **D3** App Intents (moon/planet/ISS) · **D4** observation log (SwiftData) + favorites + Messier progress ring · **D5** photo capture & share · **D6** VoiceOver labels + selection announcements (localization part pending)
- **E4** 3D orrery
- **F1** CI workflow (at `ci/ci.yml` — see below) · **F2** `Scripts/fetch_hyg.sh` deep star catalog

New epics (fully built):
- 🔭 **Telescope Guide** — `Core/Optics/*`: optics math, visibility/difficulty, tonight placement, mount guidance, observing tips, equipment library (beginner help + presets); UI: `EquipmentEditorView`, `EyepiecePreviewView`, `TelescopeSection` (in ObjectDetail), `ObserveTonightView` (Catalog). Deep-sky sizes in `Core/Catalog/DeepSkySizes.swift`.
- 🪐 **Scale AR** — `Core/Models/*` (catalog + scale math) + `AR/ScaleModelBuilder`, `AR/ScaleModelTexture`, `AR/ScaleARView`, `UI/ExploreTabView` (5th "Explore" tab). Real 2K textures in `AstroSky/Textures/` via `Scripts/fetch_textures.sh` (Solar System Scope, CC BY 4.0), procedural fallback.

Session of 2026-07-09 (committed on `feature/world-class-roadmap`, **push pending** — see CI note):
- **F3** Swift 6 language mode + full strict concurrency. `SWIFT_VERSION` 5→6. Fixes: App Intent static metadata `var`→`let` (`Intents.swift`); `SkySceneBuilder` & `ScaleModelBuilder` marked `@MainActor` (UIKit/RealityKit builders, all callers already main-actor). Build clean, 63/63 tests pass.
- **E3** iPad & landscape. iPhone orientations now portrait + landscape L/R (`INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone`); iPad was already all-orientation + `TARGETED_DEVICE_FAMILY=1,2`. `CatalogView` refactored `NavigationStack`→adaptive `NavigationSplitView` (selection-driven sidebar + detail `NavigationStack`; inner drill-downs unchanged). Verified two-column layout on iPad Pro 11" sim.
- **D6** Spanish (es) localization. Added String Catalogs `Localizable.xcstrings` (201), `AstroSky-InfoPlist.xcstrings` (3), `AppShortcuts.xcstrings` (3) via `LocalizationPlanner`; all 207 strings translated es (0 untranslated). Dynamic Type: text was already semantic; content SF Symbols (object-detail header, onboarding hero) now scale via `@ScaledMetric`. AR HUD glyphs left fixed (fixed geometry).

Overnight session of 2026-07-09/10 (committed on `feature/world-class-roadmap`, **push pending**):
- **Custom glyph system** (`UI/Design/AstroGlyphs.swift`): drawn planets (ringed Saturn), sun/moon, per-type deep-sky glyphs, real constellation stick-figure thumbnails, star/satellite/asteroid glyphs. Applied across catalog rows, detail headers, Tonight, search, AR info card. **App icon** (ringed planet on starfield) via `Scripts/generate_appicon.swift`.
- **QA fixes**: constellation detail view + tappable rows; deduped CSS satellite passes; orrery first-paint; seeing-stars rating; deep-sky dedup; HUD chip wrap.
- **Telescope**: rewrote `EyepiecePreviewView` into a realistic, to-scale eyepiece sim (field stars, per-type morphology, planet disks w/ phase, lunar phase). Selectable eyepiece; decimal focal lengths (`decimalPad`); centered card. **Real photo ↔ eyepiece side-by-side** and detail hero via `ObjectImagery` + `ObjectPhotoView` (async, cached, ImageIO-downsampled).
- **Real imagery**: `Scripts/fetch_object_images.sh` (REST originalimage + local `sips`, throttled, size-guarded) → **175 bundled photos** in `ObjectImages/` (all Messier + NGC highlights + 59 named stars via `fetch_star_images.sh`; only NGC 4631 lacks one). Wired into detail hero, telescope side-by-side, and **AR deep-sky sprites** (billboarded, favor named showpieces, cap 40, loaded post-first-paint).
- **Sky view**: persisted free-look (non-AR VR) mode (Settings + HUD); textured + oversized planets (2K maps); steeper star size-vs-magnitude + spikes ≤mag 1.5 (pro look); forgiving zoom-aware tap tolerance.
- **Explore**: height-above-surface slider (0–1.8 m).
- **Performance**: off-main image decode + NSCache; cached altitude-chart samples; `CelestialObject: Sendable` → Observe Tonight loop off-main; throttled satellite ground-track + meteor set. All fixes from a full perf audit; no per-frame regressions. 63/63 tests pass throughout. Device-verified on iPhone 17 Pro sim.
- **Known caveats**: star "photos" are Wikipedia lead images — a few are locator charts, not disk photos (stars are point sources). NGC 4631 has no image (falls back to glyph). AR DSO sprites only for the ~40 brightest/named (fainter keep ring glyphs).

## DONE this session but NOT yet pushed
`feature/world-class-roadmap` has 4 new local commits (CI, F3, E3, D6) that **cannot be pushed** until the git token gains `workflow` scope (the branch history contains `.github/workflows/ci.yml`). Recover with:
```bash
cd /Users/brian/Desktop/AstroSky
gh auth refresh -s workflow      # opens browser; approve the device code
git push origin feature/world-class-roadmap
```
Once pushed, CI activation is fully complete (workflow already moved to `.github/workflows/ci.yml`).

## REMAINING — each needs a one-time Xcode action in **AstroSky.xcodeproj**, then code I can write
Only the WidgetKit/watchOS/Live-Activity items are left; all three are blocked on creating a target in Xcode (I can't edit `project.pbxproj` without corrupting the open project).

### 1. D2 — WidgetKit widgets
- **Xcode steps to create the target:**
  1. Open `AstroSky.xcodeproj`. Menu **File ▸ New ▸ Target…**
  2. Platform **iOS**, choose **Widget Extension**, **Next**.
  3. Product Name: `AstroSkyWidgets`. **Team**: none needed (Simulator). **Uncheck** "Include Live Activity" for now (add later for E2) — or leave checked if you want the E2 scaffold. **Uncheck** "Include Configuration App Intent" unless you want configurable widgets. **Finish**.
  4. When prompted **"Activate scheme?"** → **Activate** (creates the widget scheme).
  5. Select the **project** ▸ target **AstroSkyWidgets** ▸ **General** ▸ confirm Min Deployments matches app (iOS 26).
  6. **Share the engine with the widget:** for each engine file the widget needs — `Core/Astronomy/*` (AstroTime, Sun, Moon, Coordinates, AstroMath, Nutation, RiseSet, Planets), `Core/Satellites/*` (Satellite, SatelliteService, SGP4, TLE), `Core/Location/*`, `Core/Catalog/SolarSystemObjects` — select the file in the navigator, open the **File Inspector** (right pane, ⌥⌘1), and under **Target Membership** tick **AstroSkyWidgets**. (Cleaner alternative: File ▸ New ▸ Target ▸ **Framework** `AstroKit`, move the engine there, link it to both app + widget — more work but avoids per-file membership drift.)
  7. If widgets read favorites / last location, add an **App Group** (Signing & Capabilities ▸ + App Groups ▸ `group.com.example.AstroSky`) to both app and widget so they share `UserDefaults`/`Observer.lastKnown`.
- **Then tell me it's created** and I'll write: small moon-phase widget (reuse `MoonPhaseView` drawing), medium "Tonight" (sunset/moonrise/best planet), small "Next ISS pass" (`SatelliteService.cachedSatellites()` + `Observer.lastKnown`), timelines refreshing ~4×/day.

### 2. E1 — watchOS companion
- **Xcode steps:**
  1. **File ▸ New ▸ Target…** ▸ platform **watchOS** ▸ **App** ▸ **Next**.
  2. Product Name e.g. `AstroSky Watch`. If offered, choose **"Watch App for iOS App" / companion** so it pairs with AstroSky (bundle id becomes `com.example.AstroSky.watchkitapp`). **Finish** ▸ **Activate** scheme.
  3. Share the same engine files as D2 via **Target Membership** (or link the `AstroKit` framework if you factored one). Note RealityKit/ARKit/UIKit-only files must NOT be added to the watch target — only the pure-Swift engine (`Core/Astronomy`, `Core/Satellites`, `Core/Location`, relevant `Core/Catalog`).
- **Then I'll write:** moon phase + rise/set, "next pass", and "what's up now" (brightest objects currently up), all from the shared engine.

### 3. E2 — Live Activity (satellite pass) — depends on D2
- Ships **inside** the D2 widget extension. In Xcode set **Info ▸ `NSSupportsLiveActivities` = YES** on the app target (Signing & Capabilities may add it), and if you unchecked it in step D2.3, add an `ActivityConfiguration` file to the widget target.
- **Then I'll write:** start a Live Activity ~30 min before a favorited pass; countdown → live alt/az during → end; Dynamic Island layouts.

_(E3, F3, D6, and the CI file move are DONE — see the section above and the DONE list.)_

## Optional / branding
- Renaming the app "AstroSky" → "AstronomyApp" is a separate task (scheme/product name/bundle id) — doable in the AstroSky project on request. It is NOT required for anything above.

## Helper scripts
```bash
bash Scripts/fetch_hyg.sh        # dense HYG star catalog → AstroSky/hygdata.csv
bash Scripts/fetch_textures.sh   # 12 Solar System Scope 2K maps → AstroSky/Textures/ (CC BY 4.0)
```

## Later enhancements noted
- Scale AR 8K textures streamed from a Mac-mini server (HTTP + on-device cache + offline fallback) — v1 uses bundled 2K.
- B2 comets + live JPL SBDB element fetching (v1 uses curated osculating elements for the 3 bright asteroids).

## First message to paste into the new session
> This is AstroSky at `~/Desktop/AstroSky/AstroSky.xcodeproj` (GitHub btheis15/astronomy-app). Read `HANDOFF.md` and `ROADMAP.md` in the repo root. E3/F3/D6 and the CI file move are already done and committed on `feature/world-class-roadmap`. I've now created the `AstroSkyWidgets` (and/or watchOS) target in Xcode — continue with D2/E1/E2 (widgets, watch, Live Activity). Build with `BuildProject` / xcodebuild for the iPhone 17 simulator, commit as you go, and don't edit project.pbxproj directly.
