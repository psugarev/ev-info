# EV Info — App Store readiness audit

**App:** EV Info (`com.evinfo.app`) · SwiftUI / SwiftData / CoreBluetooth / CoreLocation
**Audited:** 26 Nov 2026 · Xcode 27.0 (27A266a), release build succeeds, iPhone 18 Pro simulator run
**Scope:** every file in the project (`project.yml`, `Resources/`, all 27 `Sources/` files, `Tests/`, docs)

---

## 1. Verdict

**The app is technically solid and genuinely differentiated, but as of today it would not pass App Review.**

| Layer | State | Score |
|---|---|---|
| OBD/ELM327 engine, parsing, tests | Disciplined, read-only, 71 passing tests | 9/10 |
| Data model & storage | Works, but unbounded growth, no migration plan | 5/10 |
| UI/visual design | Coherent dark theme, but dense, fixed-size type, fake zeros | 6/10 |
| First-run / reviewer experience | Nothing without a dongle | 2/10 |
| App Store packaging | Privacy manifest, iPad claim, metadata missing (fixed in part today) | 3/10 |
| Market position | Best-in-class 192-cell BMS view + local tariff — nobody else does this | 8/10 |

The single most likely rejection is **not code**: a reviewer launches the app without an ELM327 adapter and an Ioniq 5, sees `BLE unsupported` / `0 %` / `0 V` / `0.0 kW` everywhere, and rejects under **Guideline 2.1 (App Completeness)** or **4.2 (Minimum Functionality)**. Everything else is fixable in a short, ordered sprint.

There *is* a real market: [EV Dashboard](https://apps.apple.com/us/app/ev-dashboard/id1551133542) sells for **$12.99** (4.8★), [Leaf Spy Pro](https://apps.apple.com/us/app/leaf-spy-pro/id967376861) for **$22.99**, [OBD Fusion](https://apps.apple.com/us/app/obd-fusion/id650684932) for **$9.99** with 19,641 US ratings, and [Car Scanner ELM OBD2](https://apps.apple.com/bg/app/car-scanner-elm-obd2/id1259933623) is the free generic leader in the BG store (4.8★, 1,663 ratings). None of them does a Hyundai E-GMP 192-cell view or Bulgarian day/night tariffs.

---

## 2. What I fixed today (verified)

These were unambiguous submission blockers; they are done and verified in the built bundle:

| Change | File | Verification |
|---|---|---|
| Added privacy manifest (`UserDefaults` / `CA92.1`, no tracking, no collected data) | `Resources/PrivacyInfo.xcprivacy` (new) | present at bundle root after Release build |
| Purpose strings now say **EV Info**, explain the adapter and the "stays on iPhone" model; removed deprecated `NSBluetoothPeripheralUsageDescription` | `project.yml` → `Resources/Info.plist` | rebuilt plist inspected |
| `ITSAppUsesNonExemptEncryption = false` (no export-compliance prompt per upload) | `project.yml` | in built plist |
| `LSApplicationCategoryType = public.app-category.utilities` | `project.yml` | in built plist |
| `UIRequiredDeviceCapabilities = [arm64, bluetooth-le]` (honest hardware requirement) | `project.yml` | in built plist |
| iPhone-only for v1 (`TARGETED_DEVICE_FAMILY = 1`), portrait | `project.yml` | `UIDeviceFamily = [1]`, removes "all orientations" iPad warning |
| `UISupportedInterfaceOrientations`, `UILaunchScreen {}` | `project.yml` | in built plist |
| Export filenames `ioniqdrive-*` → `ev-info-*`; JSON `"app": "EV Info"` | `ExportService.swift`, `LogsView.swift` | grep clean |
| About version read from bundle instead of hardcoded `1.0` | `SettingsView.swift:12` | builds |

Release build: **BUILD SUCCEEDED**, `PrivacyInfo.xcprivacy` confirmed inside `IoniqDrive.app`.
Unit tests: **71 passed** (`swift test --disable-sandbox`).

Note: the Xcode project is XcodeGen-generated, so always edit `project.yml` and run `xcodegen generate`; hand edits to `Info.plist` are overwritten.

### 2b. Implemented in the follow-up pass (27 Nov 2026)

Verified by: `swift test` (84 passed: 71 original + 13 new), Release build succeeded, Debug build run in the iPhone 18 Pro simulator (first-run disclaimer, Drive screen in demo mode).

| Audit item | What was done | Where |
|---|---|---|
| B1 demo mode | User-facing **Settings → Demo mode** (off by default) with recorded sample session + 24 h history; labelled `DEMO`; history seeded only if the store is empty and removed again on switch-off | `Sources/App/DemoData.swift`, `IoniqDriveApp.swift`, `SettingsView.swift` |
| B1 fake zeros | Unavailable values render `—` (Drive, Charging); `hasBMSData` / `bmsText` / `positiveText` on `TelemetryEngine` | `TelemetryEngine.swift`, `DashboardView.swift`, `ChargingView.swift` |
| B1 empty state | Drive card "Connect your OBD2 adapter — or explore with demo data" with **Connect** and **Use demo data**; tappable status header | `DashboardView.swift` |
| B1 review notes | Written | `Distribution/APP_REVIEW_NOTES.md` |
| B2 background location | `location` background mode and `allowsBackgroundLocationUpdates` removed (foreground trip recording only) | `project.yml`, `LocationManager.swift` |
| B3 provenance | `BMS · CANDIDATE` badge, `POWER · DERIVED`, speed row with `GPS`/`OBD` source chip; dev-language footnote moved into the info sheet | `DashboardView.swift`, `BatteryDetailView.swift` |
| B4 policy / notes | Privacy policy and review notes drafted (placeholders: contact email, date, video link) | `Distribution/` |
| H1 Bluetooth prompt | `CBCentralManager` created lazily on first Connect (or at launch only if an adapter was used before); Settings deep link when denied; no auto-scan | `BLETransport.swift`, `SystemSettings.swift` |
| H2 storage | Retention setting (30/90/365/forever, default 90), launch purge off-main, cascade delete of a trip's raw frames, **Delete all data**, predicated + limited `RawLogView` query | `DataRetention.swift`, `SettingsView.swift`, `TripHistoryView.swift`, `RawLogView.swift` |
| H3 export | Generated on tap, off the main thread, with 7 d / 30 d / All range, 100 k-row cap and progress; shared date formatter | `ExportService.swift`, `LogsView.swift` |
| H4 migrations | `SchemaV1` + `AppMigrationPlan`; `try!` removed; storage failure now shows a banner instead of silently going in-memory | `AppSchema.swift`, `IoniqDriveApp.swift` |
| H5 disclaimer | First-run disclaimer, footnote on Battery / Charging / Settings, not-affiliated text | `DisclaimerView.swift` |
| H6 (partial) | 57 new Bulgarian strings; `InfoPlist.xcstrings` with BG purpose strings; `CFBundleLocalizations` | `Localizable.xcstrings`, `InfoPlist.xcstrings`, `project.yml` |
| H7 location denied | Banner with Settings link on the trip card | `DashboardView.swift`, `LocationManager.swift` |
| H8 (partial) | `textTertiary` raised to `#8CA0B8` (≈6.7:1); accessibility grouping on new cards | `Theme.swift` |
| P0 #2/#3/#4 | Remembered adapter + auto-reconnect; stale badge (`STALE` + dimmed values after 3 s); compact speed row | `BLETransport.swift`, `DashboardView.swift` |
| Misc | `print()` → `os.Logger`; stale `RootTabView` comment fixed | `AppLog.swift` |

**Still open (not done in this pass):** dynamic-string localisation (BLE status text, diagnostics, trip summaries, chart titles) and purging stale `Localizable` keys; Dynamic Type migration of the ~55 fixed font sizes, remaining hit-target and Reduce Motion fixes; connect-step progress text during `ATZ` init; all P1/P2 features (charge-session log, DTC read, units, cell analytics redesign, per-trip export, haptics, charts, widgets, daylight theme); colour-semantics cleanup and hard-coded SwiftUI colours outside the files touched; onboarding pages; App Store Connect items that cannot live in the repo (privacy-policy hosting, screenshots, age rating, DSA trader status, hardware video). Background trip logging remains unvalidated, which is why the mode was dropped rather than shipped.

---

## 3. Blockers that still stop submission

### B1 — No demo mode → virtually guaranteed 2.1 / 4.2 rejection
Every tab reads live BLE telemetry; there is no demo, sample or preview data path anywhere (`grep demo/mock/sample` → only a test fake).
Worse, when data is missing the UI shows **plausible-looking zeros**, not "—": `DashboardView.swift:146,159-164`, `ChargingView.swift:66,74`. A reviewer has no way to see the product.

**Do:**
1. `DemoTelemetrySource` that emits a canned `TelemetrySample` stream (reuse the real capture already in `Tests/OBDResponseParserTests.swift`) — one toggle in Settings.
2. Replace every unavailable value with `"—"` and dim it (Battery Detail already does this correctly via `percent()`/`volts()` helpers — `BatteryDetailView.swift:253-271`).
3. Drive empty state: “Connect your OBD2 adapter — or explore with demo data”, with a **Connect** button.
4. Put the demo path in the App Review notes.

### B2 — Background location mode declared, behaviour unverified
`UIBackgroundModes = [bluetooth-central, location]` and `allowsBackgroundLocationUpdates = true` (`LocationManager.swift:57,109`), but the README itself lists background behaviour as *not validated*, and only `requestWhenInUseAuthorization()` is ever called (`:33`). Guideline **2.5.4** rejections are common when a reviewer cannot find a feature that needs the mode.

**Do:** either validate background trip logging on the iPhone and demo it in review notes, or drop `location` from `UIBackgroundModes` for v1 (foreground recording only). Keep `bluetooth-central` — it is genuinely used.

### B3 — “Candidate” data presented as authoritative
The BMS decode is not cluster-correlated (README:56-62 admits it; the car's `0100` bitmap only advertises PIDs `01`/`20`, so there is no OBD speed/RPM). Yet Drive shows SOC/pack/power/temps with no marker, and the only caveat is one footnote (`BatteryDetailView.swift:135`). It is also a **2.3 Accurate Metadata** issue if the store description claims accuracy you have not validated.

**Do:** per-tile provenance badges (`candidate` / `derived` / `GPS`) using the existing `MetricSource` enum; write the description only around validated claims (read-only telemetry, 192 cell voltages, trips, costs, tariff) and add “not affiliated with Hyundai”.

### B4 — No App Store Connect artefacts
No screenshots, no privacy policy, no support URL, no age-rating answers in the repo. ASC hard-requires all of these, plus a **privacy policy URL for every app**.

**Do:** privacy policy page (template below), support URL (GitHub Issues is acceptable), 6.9-inch + 6.5-inch screenshot sets, age rating 4+.

---

## 4. High-risk items (fix before or right after launch)

| # | Issue | Where | Fix |
|---|---|---|---|
| H1 | Bluetooth permission prompt fires at first launch, no context, no "Open Settings" recovery, scan starts automatically | `BLETransport.swift:71,144-151`, `IoniqDriveApp.swift:33` | create `CBCentralManager` lazily on first Connect tap; add a pre-permission screen; on denied, show a Settings deep link |
| H2 | Unbounded always-on storage: 1 row/s telemetry, every raw frame per trip, no retention, no delete-all, deleting a trip orphans raw frames, `RawLogView` loads the whole table | `TelemetryStore.swift:39-43`, `TripRecorder.swift:63-78`, `TripModels.swift:47`, `TripHistoryView.swift:38-43`, `RawLogView.swift:11` | retention setting (30/90 days, closed-loop cap), cascade delete raw frames by `tripID`, predicated `@Query`, "Delete all data" in Settings |
| H3 | Export builds all JSON/CSVs on the main thread in `.onAppear` → watchdog risk on a long history | `LogsView.swift:113-129`, `ExportService.swift:106-121` | generate on tap, off-main, with a range picker/row cap and a progress indicator |
| H4 | SwiftData has no migration plan; on any schema error the app silently falls back to **in-memory** (data loss) and uses the only `try!` in the codebase | `IoniqDriveApp.swift:11-27` | `VersionedSchema` + `SchemaMigrationPlan`; surface "storage unavailable" instead of silently dropping persistence |
| H5 | No disclaimer for a safety-adjacent product that prints PASS/WARN/**FAIL** battery verdicts | `VehicleDiagnostics.swift:78,86,97,102,107` | one-time disclaimer + `InfoCard` on Battery/Diagnostics: informational only, not a substitute for service inspection, don't use while driving |
| H6 | Bulgarian localisation stops at the view layer: 33 keys without `bg`, and all dynamic strings are English — BLE statuses, diagnostic names/details, trip summaries, chart titles | `Localizable.xcstrings`, `BLETransport.swift`, `VehicleDiagnostics.swift`, `TripSummaryGenerator.swift`, `BatteryHistoryView.swift:122` | make them `String(localized:)`/`LocalizedStringKey`, translate, purge 38 stale keys, add `InfoPlist.xcstrings` |
| H7 | Denied location is invisible; trips record 0 km with no explanation | `LocationManager.swift:99-113`, `TripHistoryView.swift:58` | banner + Settings deep link; show recorded distance source |
| H8 | Accessibility: 55 fixed font sizes (~34 at ≤11 pt), 3 accessibility labels total, `textTertiary` 3.77:1 on cards (fails WCAG AA), two sub-44 pt targets, Reduce Motion ignored | `Theme.swift:98-127`, all views | Dynamic Type system (see §5), contrast fix, labels on gauges/grid, hit-target padding |

Medium/low: deprecated key removal (done), `print()` → `os.Logger`, `ISO8601DateFormatter` allocated per row, `TripRecorder.samples` grows for the whole trip, `purgeTimer` never invalidated, hardcoded `€` formatting, stale docs (README says "bar/psi toggle" and "179 keys" — neither is true; the psi branch `TirePressureView.swift:130` is unreachable because nothing writes that `@AppStorage`).

---

## 5. Functions → what to build, in order

### P0 — required to ship (≈1–2 weeks of focused work)
1. **Demo mode + "—" for unavailable + Drive connect empty state** (B1). *Acceptance: fresh install, no dongle → all five tabs fully browsable and screenshots are presentable.*
2. **Connect as a first-class action**: tappable status header → adapter sheet; remember last adapter; auto-reconnect; explicit disconnect; spinner with step text during `ATZ`+init (up to ~20 s of silence today). *Acceptance: returning user reaches LIVE in ≤5 s with zero taps.*
3. **Data age / stale badge**: grey the LIVE chip and stamp values when the last sample is >3 s old. *Acceptance: unplugging the adapter flips the UI to stale within 3 s instead of showing frozen numbers.*
4. **Compact speed readout with source chip** (`GPS` until OBD speed is validated) — you asked for no big speed hero; a one-line row respects that. *Acceptance: speed visible on Drive, marked GPS, no hero.*
5. **Storage hygiene**: retention setting, cascade delete of raw frames, delete-all, predicated queries (H2).
6. **Disclaimer + About disclaimer text** (H5) and **privacy policy + support URL** (B4).
7. **Localise dynamic strings** (H6) — at minimum BLE statuses, diagnostics, trip summaries.
8. **InfoPlist.xcstrings** with BG purpose strings.

### P1 — table stakes vs the competition
9. **Charge-session log with cost**: detect start/end, integrate kWh, price by tariff, list in Charging + Costs. *Today Charging only shows BMS lifetime counters — a reviewer sees "AC 456 / DC 209" that you cannot influence, not "your sessions".*
10. **Read-only DTC scan (Mode 03/07/0A)** — never clear. Biggest missing capability vs Car Scanner; it is also the #1 reason people install an OBD app.
11. **Units setting** (metric/imperial, bar/psi, € currency) and make the tire psi control actually exist.
12. **Cell analytics**: weakest/strongest cell, per-module (32-cell block) min/max/Δ, balance trend from snapshots. This is your differentiator — currently buried under a 1,300-pt wall of decimals.
13. **Per-trip export (CSV/GPX) and backup/restore** — currently only whole-dataset export.
14. **Haptics + toast + confirmation/undo** for start/stop, tests, save, delete, export.

### P2 — differentiators (post-launch)
15. Chart system: time-range picker, scrubbing, axis units, accessibility descriptors.
16. Local notifications: charge complete, 12 V low, tire low.
17. Widgets + App Intents ("SOC", "start trip").
18. Glance/driving mode (≤5 values, ≥40 pt, keep-awake).
19. SoH degradation tracker (SoH vs km/time).
20. Landscape instrument layout; later iPad, Watch mirror, CarPlay (entitlement-gated).

**Deliberately out of scope** (say so in the listing): DTC clearing, any actuator/coding/remote command (impossible over OBD, and violates rule 1 in `AGENTS.md`), cloud accounts, multi-vehicle until a second car is validated.

---

## 6. Visual → what to change, concretely

Current Drive screenshot (simulator, no adapter) shows the core problems at a glance: five different values rendered as `0`, no speed, no connect CTA, a full-width cyan START TRIP button as the loudest element on screen, and a card stack where every card has the same weight.

1. **Kill the fake zeros.** Unavailable = `—` + `textTertiary`. This is trust, not cosmetics. (`DashboardView.swift:146-168,383-390`, `ChargingView.swift:66-94`.)
2. **Type system instead of 55 hard-coded sizes.** Build `Theme.font(_ style: TextStyle)` mapping to `.custom(size:relativeTo:)`; minimum 12 pt for labels, 13–14 pt for captions, `@ScaledMetric` for hero numbers. No label below 12 pt. Verify at AX3/AX5.
3. **Contrast:** raise `textTertiary` `#64748B` → ≈`#8CA0B8` (≥4.5:1 on `#111722`); `CardLabel` at 11 pt + `tracking(1.4)` is currently 3.77:1 — the only label for most metrics.
4. **Hierarchy:** one hero per screen. Drive's hero should be the car's state (SOC ring), not a full-width cyan START TRIP. Make trip start a secondary (outlined) control and keep a recording chip when active.
5. **Colour semantics — make them exclusive:** cyan = live/selected, green = positive energy (regen/charging/OK), amber = attention, red = fault; cost becomes neutral text (today amber = money on Costs and warning elsewhere; green means four different things).
6. **Remove hard-coded SwiftUI colours** (`.blue/.green/.orange/.purple/.yellow`, 20 sites in TripHistory, Logs, BatteryHistory, CellVoltage) — route everything through `Theme` so the palette stays a system.
7. **Cell grid redesign (your best screen).** Six labelled 32-cell module blocks, min/max highlighted, threshold legend, weakest-cell ranking, tap-a-cell detail. Today: 6×32 tiles of 8 pt indices, no grouping, no legend — a wall.
8. **Charts:** add range picker, scrubbing with a value callout, unit labels, theme colours; stop `catmullRom` on step-like data.
9. **First-run art/direction:** 3 onboarding pages (what it reads, what you need, privacy "everything stays on the phone"), and a proper empty state on Drive.
10. **Daylight/high-contrast theme** option — `#06080D` on a sunny dashboard is unreadable; a "Daylight" token set is a real in-car requirement, not a nicety.
11. **Consistency cleanup:** settings gear is leading on Drive but trailing everywhere else; two different card radii/paddings; a stale doc string in `RootTabView.swift:4-5` still claims a Tires tab; `BatteryDetailView` bottom footnote exposes dev language ("candidate … not compared with the car's dashboard") to users — move it into the info sheet.
12. **App icon** is submission-ready (1024 px, no alpha) — keep the mushroom; it is memorable and distinctive.

---

## 7. App Store Connect checklist

**Requirements as of Nov 2026** (per Apple's [Upcoming Requirements](https://developer.apple.com/news/upcoming-requirements/)): builds must use Xcode 26+ / iOS 26 SDK since 28 Apr 2026 (your Xcode 27 satisfies it), minimum deployment target iOS 13, new age-rating questions since Jan 2026, and **EU DSA trader status is mandatory** — you are in Bulgaria, so without verified trader status the app is removed from the EU store.

| Item | Status | Action |
|---|---|---|
| Privacy manifest | ✅ added | keep in sync if you add analytics/cloud |
| Export compliance | ✅ set | — |
| App category | ✅ Utilities | — |
| iPhone-only | ✅ set | — |
| Privacy policy URL | ❌ | publish "all data stays on device; no analytics; export only via share sheet" |
| Support URL | ❌ | GitHub Issues page is enough |
| Screenshots 6.9" + 6.5" | ❌ | must be captured in **demo mode**; no device frames, no text overlays (Guideline 2.3.3) |
| Age rating questionnaire | ❌ | 4+ |
| DSA trader status | ❌ | App Store Connect → Compliance |
| App Review notes | ❌ | explain adapter requirement + demo mode + read-only policy |
| Hardware demo video | ❌ | Apple requires a **video (not a screen recording) of the app running on a physical device pairing with the hardware** for apps that need hardware ([App Review help](https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review/)) |
| Privacy label | — | "Data Not Collected" (verified: no `URLSession`, no analytics, no accounts) |
| IAP | — | none now; if you charge later, use StoreKit (3.1.1), no external links |

**Positioning text (draft):** "EV Info reads your Hyundai/Kia E-GMP battery over an ELM327 Bluetooth adapter: state of health, all 192 cell voltages, temperatures, 12 V and LDC, charging power, tire pressures, trips and real electricity cost — computed on your iPhone, nothing sent to a server. Read-only: it never writes to the car. Requires a BLE ELM327-compatible adapter (e.g. vLinker iCar Pro). Not affiliated with Hyundai Motor Company."

**Naming:** "EV Info" is neutral and safe, but generic and hard to find. If you ever want the Ioniq audience, keep the trademark out of the *name/subtitle/keywords* and put compatibility in the description ("works with Ioniq 5 / EV6 / GV60"). Distinctive candidates: **CellScope**, **VoltScope**, **PackPulse**, **EV Insight**. Avoid "IONIQ" in the name — a competitor already ships "IONIQ Telemetry", which is exactly the kind of name Hyundai can ask Apple to pull.

---

## 8. Monetization

Free download + **one-time Pro unlock (€9.99, launch €6.99)**: free = live Drive/Battery/Cells, connection, diagnostics summaries; Pro = history & charts, cell analytics, trip/cost engine, export/backup. No subscription in v1 — there is no server cost, and this audience punishes subscriptions (Car Scanner still sells lifetime). Do not use a tip jar.

---

## 9. Suggested sequence

**Week 1 (make it reviewable):** demo mode + "—" everywhere + connect flow + stale badge → disclaimer + privacy policy/support page → screenshots in demo mode → review notes. *This is the minimum to submit.*
**Week 2 (make it credible):** retention/delete-all, cascade delete, off-main export, migration plan, Dynamic Type + contrast pass, cell-grid redesign, dynamic-string localisation.
**After approval:** DTC read, charge sessions with cost, units, widgets, chart scrubbing, daylight theme.
**Later:** landscape/instrument mode, iPad, Watch, CarPlay (file the entitlement early — it takes weeks).

---

## 10. Evidence

- Everything above is from a full read of the repository; audits cross-checked against a Release build and a simulator run.
- Simulator run of the unconnected Drive screen confirmed in person: `BLE unsupported` header, `0 %` / `0 V` / `+0.0 A` / `0.0 kW` / `0 °C`, no speed row, no connect CTA, and a full-width cyan START TRIP as the loudest element.
- Tests: 71 passing (`swift test --disable-sandbox`), Release build succeeded, privacy manifest in bundle.

---

## Appendix A — privacy policy draft (host this at a public URL)

> **EV Info — Privacy Policy**
> EV Info reads vehicle data from an ELM327-compatible Bluetooth OBD2 adapter and stores it locally on your iPhone.
>
> **What the app collects:** none. There is no account, no server, no analytics, no advertising and no third-party SDK. Trip data, battery history, diagnostic reports, GPS track points and settings stay in the app's local storage on your device.
> **Location:** used only while you record a trip, to measure distance, speed and route when the car does not report them over OBD2. Reverse geocoding of trip start/end is performed by Apple's CoreLocation service.
> **Bluetooth:** used only to connect to your OBD2 adapter.
> **Export:** files (JSON/CSV) are created on your device only when you tap Share, and go wherever you send them.
> **Deleting data:** trips can be deleted in the app; deleting the app removes all stored data.
> **Contact:** <your email>
> Last updated: <date>

## Appendix B — App Review notes draft

> EV Info is a read-only telemetry app for EVs. It needs a Bluetooth LE ELM327-compatible OBD2 adapter (we use vLinker iCar Pro) plugged into the car's OBD port.
>
> Review without hardware: open Settings (gear, top of any tab) → **Demo mode** — the app then shows a recorded real session (battery, 192 cell voltages, charging, trips, costs) so every screen can be evaluated. Demo mode is off by default.
>
> The app never sends actuator, coding or clear-diagnostic commands — it only reads Mode 01 and UDS `22` data, plus GPS while recording a trip. All data stays on device; no account is required.
>
> A short setup video showing the app pairing with the adapter on a physical iPhone: <link> (Apple requires a video, not a screen recording, for apps with required hardware).
>
> EV Info is not affiliated with or endorsed by Hyundai Motor Company. Hyundai and Ioniq are trademarks of Hyundai Motor Company.

## Appendix C — screenshot shot list (6.9" and 6.5", demo mode)

1. Drive — connected, SOC ring, speed row, power, tire state.
2. Battery — SoH, remaining energy, 12 V/LDC, pack summary.
3. Cells — the redesigned module blocks with weakest cell highlighted (this is the differentiator; make it screenshot #2 if it looks stronger).
4. Charging — current power, session curve, AC/DC split.
5. Costs — month total, €/100 km, day/night split, tariff card.
6. Trip detail — map/route or summary with distance, energy, cost.

Rules: no device frames, no marketing text baked into the image (Guideline 2.3.3), no empty/zero states, keep the same device family and order as the listing.

## Appendix D — listing copy draft

- **Name (30):** EV Info — EV battery & OBD2
- **Subtitle (30):** Battery, cells, charging, costs
- **Promotional text:** See what your EV's BMS is really doing: state of health, all 192 cell voltages, temperatures, charging power, tires, trips and real energy cost — computed on your iPhone, nothing uploaded.
- **Keywords:** OBD2,ELM327,EV,battery,SoH,cell voltage,charging,trip,cost,telemetry,E-GMP,Ioniq
- **What's New (1.0):** First release: read-only OBD2 telemetry, 192-cell BMS view, charging and cost tracking, trips with local summaries, JSON/CSV export.
