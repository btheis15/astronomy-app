# AstroSky 🌌

A native iOS AR astronomy app in the spirit of SkyView — point your iPhone at the sky and see stars, planets, constellations, Messier objects and live satellites (including the ISS and Starlink) overlaid on the camera view, in the right place, in real time.

Built entirely with the modern Apple stack: **SwiftUI**, **ARKit + RealityKit**, **Swift Charts**, **CoreLocation** and the `@Observable` macro. No third-party dependencies — the planetary ephemeris and the SGP4 satellite propagator are implemented in pure Swift in this repo.

## Features

### AR Sky view
- **Camera passthrough AR** with `.gravityAndHeading` world alignment — the celestial sphere is geographically aligned, so Jupiter in the app is Jupiter in the sky.
- **Star field** rendered as a handful of batched meshes (color-bucketed by B−V index) — smooth even with thousands of stars.
- **Constellation stick figures** (35 constellations) with names, **Messier object markers** (all 110), planet/Sun/Moon markers, and a compass horizon ring.
- **Live satellites**: the ISS, Hubble and the rest of Celestrak's naked-eye "visual" group, plus an optional 300-satellite **Starlink** layer, propagated with SGP4 in real time.
- **Tap to identify** anything, with a magnitude-weighted picker so tapping near Jupiter picks Jupiter.
- **Search & guide**: search anything ("Vega", "M31", "ISS", "Andromeda"), then follow the on-screen arrow to find it.
- **Time travel**: scrub ±12 h or jump by hours/days; the whole sky (planets, Moon, satellites) recomputes.
- **Manual mode** (drag to look around, pinch to zoom) — automatic on Simulator/devices without AR, or toggle it any time.
- **Night vision mode**: red-tinted UI to protect dark adaptation.

### Tonight
- Sunrise/sunset, civil/astronomical twilight, solar noon.
- Moon phase (drawn, not an emoji), illumination %, moonrise/moonset.
- Every planet with live altitude/azimuth and magnitude.
- **Visible satellite passes** for the next 24 h — only passes that are actually visible (satellite sunlit, sky dark, ≥ 10° altitude).

### Catalog
- Solar system, ~200 bright stars, all 110 Messier objects, 35 constellations, live satellite lists — all searchable, each with a detail page:
  - live position (alt/az + RA/Dec), rise/transit/set times,
  - an **altitude-vs-time chart** (Swift Charts) for tonight,
  - physical data (distance, magnitude, spectral color, angular size, orbit data for satellites),
  - "Find in AR" deep link.

## The astronomy engine (`AstroSky/Core`)

| Component | Method | Accuracy |
|---|---|---|
| Time | Julian Date, GMST/LST (Meeus ch. 12) | < 0.1 s |
| Sun | Meeus ch. 25 low-precision | ~0.01° |
| Moon | Truncated ELP-2000 (Meeus ch. 47, ~30 terms/series) | ~0.05° |
| Planets | JPL Keplerian elements + rates (Standish, 1800–2050) | arcminutes |
| Precession | Rigorous ζ/z/θ rotation (Meeus ch. 21) | exact rotation |
| Rise/set | Altitude sampling + bisection refinement | seconds |
| Satellites | Full near-earth **SGP4** (Vallado AIAA 2006-6753 port) | km-level |
| Refraction | Bennett's formula | arcminute |

All catalog positions are J2000.0; positions are precessed to date for display. TLEs come from Celestrak (`stations`, `visual`, `starlink` groups), cached on disk, refreshed every 6 h, fully offline-tolerant.

## Building

1. Open `AstroSky.xcodeproj` in **Xcode 26 or the Xcode 27 beta** (the project targets iOS 26.0, so it runs on iOS 26 and the iOS 27 beta).
2. Select your development team under *Signing & Capabilities* (bundle ID is `com.example.AstroSky` — change it to yours).
3. Run on a **real iPhone/iPad** for the AR experience. On Simulator the app automatically uses manual (drag-to-look) mode.
4. Tests: `⌘U` — the astronomy engine is verified against worked examples from Meeus' *Astronomical Algorithms* and the reference ISS TLE.

> **Note on iOS 27 beta:** the app uses the current stable API surface (SwiftUI, RealityKit, ARKit, Swift Charts, Observation), which builds and runs unchanged under the iOS 27 beta SDK. No deprecated frameworks (no SceneKit).

## Deeper star catalog (optional)

Out of the box the app embeds ~200 real bright stars (every constellation-figure star plus the brightest stars of both hemispheres). For a much deeper sky:

1. Download `hygdata_v41.csv` from the [HYG database](https://github.com/astronexus/HYG-Database) (CC BY-SA 4.0).
2. Rename it to **`hygdata.csv`** and drag it into the `AstroSky` folder in Xcode (check "AstroSky" target membership).
3. Rebuild. `HYGCatalogLoader` picks it up automatically and the sky fills with every naked-eye star (magnitude ≤ 6.5). The magnitude slider in Settings controls how many are drawn.

## Architecture

```
AstroSky/
├── App/            AstroSkyApp, AppState (@Observable, time travel, settings)
├── Core/
│   ├── Astronomy/  JD & sidereal time, coordinates & precession,
│   │               Sun/Moon/planet ephemeris, rise-set/twilight, formatting
│   ├── Catalog/    CelestialObject protocol, stars, Messier, constellations,
│   │               HYG loader, unified search
│   ├── Satellites/ TLE parser, SGP4 propagator, Celestrak service, passes
│   └── Location/   CoreLocation wrapper
├── AR/             SkySceneBuilder (batched RealityKit meshes),
│                   SkyRenderer (AR/manual modes, tap-identify, guidance),
│                   SwiftUI container
└── UI/             Sky HUD, Tonight, Catalog, Detail (+ altitude chart),
                    Search, Settings, night mode
AstroSkyTests/      Swift Testing suites for the engine, SGP4, TLEs, catalogs
```

### Design notes

- **One quaternion moves the sky.** The star field, constellation lines and deep-sky markers are static meshes in the J2000 equatorial frame under a single `skyRoot` entity; sidereal rotation, observer latitude and precession are composed into one rotation, updated once a second. Time travel is free.
- **Satellites live in the world frame** (they're not on the celestial sphere) and are re-propagated every 0.5 s.
- **Everything is a `CelestialObject`** — stars, planets, the Moon, M31 and the ISS share one protocol, so search, detail pages, tap-identify and "Find in AR" work uniformly.

## Data sources & credits

- Ephemeris algorithms: Jean Meeus, *Astronomical Algorithms* (2nd ed.); JPL/E.M. Standish Keplerian elements.
- SGP4: Vallado, Crawford, Hujsak & Kelso, *Revisiting Spacetrack Report #3* (AIAA 2006-6753).
- TLE data: [Celestrak](https://celestrak.org) (live, fetched at runtime).
- Star data: Yale Bright Star Catalogue / Hipparcos values; optional deep catalog from the [HYG database](https://github.com/astronexus/HYG-Database).
