# AstroSky — Future Updates

These items require Xcode capability/entitlement setup or platform targets that don't exist yet.
Create the relevant targets/entitlements in Xcode first, then implement.

---

## WeatherKit (P4.3) — Weather-aware observing forecast

**Requires:** WeatherKit capability + entitlement (Xcode Signing & Capabilities → +Capability → WeatherKit).
Also needs a paid Apple Developer account with WeatherKit enabled in the provisioning profile.

**What to build:**
- "Conditions tonight" section at the top of the Tonight tab
- Cloud-cover %, hourly clear-sky strip for the night, go/no-go verdict
- Feeds into TonightPlanner rankings (dim or hide objects when cloudy)
- Graceful fallback when entitlement/network unavailable

---

## WidgetKit (P4.4) — Home screen & lock screen widgets

**Requires:** Widget Extension target (File → New Target → Widget Extension in Xcode).
Also needs an App Group (`group.com.example.AstroSky`) shared between app + widget targets.

**What to build:**
- Moon phase widget (small): current phase name + illustration using MoonPhaseView drawing
- "Tonight at a glance" widget (medium): next 2–3 events, moon phase, ISS pass time
- Next ISS pass widget (small): countdown + direction
- Move relevant UserDefaults reads behind a shared App Group suite so widgets can read them
- Reuse `MoonPhaseView` drawing code and `AstroGlyphs` icons

---

## iCloud Sync (P4.5)

**Requires:** iCloud capability + CloudKit entitlement (Xcode Signing & Capabilities → +Capability → iCloud → CloudKit).
SwiftData's CloudKit sync requires the container to be CloudKit-compatible (no optional relationships with non-optional inverses, etc.).

**What to build:**
- `ObservationLogEntry` SwiftData model synced via CloudKit
- `NSUbiquitousKeyValueStore` mirroring for favorites + equipment JSON
- Conflict resolution: last-write-wins for equipment, union-merge for favorites

---

## Live Activities (P4.7a) — Pass tracking on the Dynamic Island / Lock Screen

**Requires:** Live Activities entitlement + ActivityKit (Xcode Signing & Capabilities → +Capability → Push Notifications; also enable Live Activities in Info.plist).
Needs a Widget Extension target if not already created for P4.4.

**What to build:**
- Satellite pass Live Activity: countdown to AOS, current altitude/direction, time to LOS
- Launches from the pass detail view when a pass is < 10 minutes away
- Updates via `ActivityKit` push or local `Activity.update()`

---

## watchOS Companion (P4.7b)

**Requires:** watchOS App target (File → New Target → Watch App for iOS App).
Needs Watch Connectivity framework for phone→watch data transfer.

**What to build:**
- Tonight's highlights: next ISS pass + 2–3 best objects (compact list)
- Moon phase complication
- Tap an object → starts "Find in AR" on the paired iPhone via Watch Connectivity
- Reuse `MoonPhaseView` drawing (watchOS compatible SwiftUI)

---

## Full Date/Time Travel (P4.6)

No capability needed — pure SwiftUI.

**What to build:**
- Date picker button in `TimeControlBar` → compact `DatePicker` sheet for any date/time
- Keep the ±12 h slider for fine scrub alongside the date picker
- Hide TLE satellites (with explanatory note) when |offset| > 2 days (SGP4 accuracy degrades)
- Consider limiting orrery to ±100 years (Meeus approximations degrade beyond ~±3 centuries)

---

## Project Hygiene (P5.3)

**Human steps:**
1. **Bundle ID**: Change from placeholder `com.example.AstroSky` to your real reverse-domain ID in Xcode project settings (all targets).
2. **Signing**: Set `DEVELOPMENT_TEAM` in project settings; enable Automatically manage signing.
3. **Marketing version**: Bump `MARKETING_VERSION` in project settings.
4. **PrivacyInfo.xcprivacy**: Verify it appears in the built .app (Product → Show Build Folder → look inside .app bundle). Audit `NSPrivacyAccessedAPITypes` for any APIs that need required-reason declarations (e.g. `UserDefaults` → `CA92.1`).
5. **Stray stubs**: Remove the "Untitled Project" widget/watch stubs if present in the project navigator.
6. **docs/ideas/**: Consider moving `Force_Pull_Pinch_Twist_AR_Interactions.md` to `docs/ideas/` and committing it if it contains useful future ideas.
