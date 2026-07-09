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

## REMAINING — each needs a one-time Xcode action in **AstroSky.xcodeproj**, then code I can write

### 1. D2 — WidgetKit widgets
- **Xcode:** File ▸ New ▸ Target ▸ **Widget Extension** (name e.g. `AstroSkyWidgets`). Add the shared engine files to the widget target's membership: `Core/Astronomy/*` (AstroTime, Sun, Moon, Coordinates, AstroMath, Nutation, RiseSet), `Core/Satellites/*`, `Core/Location/Coordinates`… (or factor a shared framework).
- **Build:** 3 widgets — small moon-phase (reuse `MoonPhaseView` drawing), medium "Tonight" (sunset/moonrise/best planet), small "Next ISS pass" (uses `SatelliteService.cachedSatellites()` + `Observer.lastKnown`). Timeline refresh ~4×/day.

### 2. E1 — watchOS companion
- **Xcode:** File ▸ New ▸ Target ▸ **watchOS App**. Share engine files.
- **Build:** moon phase + rise/set, "next pass", and "what's up now" (brightest objects up) from shared engine.

### 3. E2 — Live Activity (satellite pass) — depends on D2
- Ships inside the widget extension. Start a Live Activity ~30 min before a favorited pass; countdown → live alt/az during → end. Dynamic Island.

### 4. E3 — iPad & landscape
- **Xcode:** Target ▸ General ▸ Deployment Info → enable iPhone **Landscape Left/Right**.
- **Code:** `NavigationSplitView` for `CatalogView` on regular width; verify HUD safe-areas in landscape (AR view already fine).

### 5. F3 — Swift 6 strict concurrency
- **Xcode:** Build Settings ▸ **Swift Language Version = 6**.
- **Code:** fix diagnostics (watch `SkyRenderer` Timer/Combine callbacks, `LocationService` delegate hops). One known spot already made `nonisolated`: `SatelliteService.groups`.

### 6. D6 — Localization (accessibility already done)
- **Xcode:** Project ▸ Info ▸ Localizations ▸ **+ Spanish (es)**.
- **Code:** add `Localizable.xcstrings`, extract user-facing UI strings, provide Spanish. Dynamic Type audit (mostly semantic fonts already).

### 7. CI activation
- Workflow is at **`ci/ci.yml`**. Move it to **`.github/workflows/ci.yml`** on GitHub (the CLI token lacks `workflow` scope; or run `gh auth refresh -s workflow` locally then push). README badge already added.

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
> This is AstroSky at `~/Desktop/AstroSky/AstroSky.xcodeproj` (GitHub btheis15/astronomy-app). Read `HANDOFF.md` and `ROADMAP.md` in the repo root. I've created the Widget/watchOS targets in this project. Continue with D2/E1/E2 (widgets, watch, Live Activity), then E3/F3/D6. Build with xcodebuild for the iPhone 17 simulator, commit/push as you go, and don't edit project.pbxproj directly.
