# EV Info (IoniqDrive)

Native Swift/SwiftUI iPhone telemetry logger for a Hyundai Ioniq 5, built for
MacBook Pro M2 + iPhone 12 Pro + vLinker iCar Pro BLE 4.0.

## Current status

Implemented and unit-tested:

- BLE connection to a vLinker/iCar ELM327 UART (known service profiles, verified
  before any command is sent).
- ELM327 init, protocol detection, supported-PID discovery.
- Header-aware request queue with timeout resync, so one slow reply cannot
  corrupt the next command.
- ISO-TP reassembly for single- and multi-frame CAN responses.
- Mode 01 decoders: speed, RPM, throttle, ambient temperature.
- VIN (`22F190` on 7E2) and odometer (`22B002` on 7C6).
- Battery health: SoH and remaining energy (`220105`), lifetime AC/DC
  charging counters and energy (`220111`), 12 V/LDC data (`22E011`), and a
  dedicated Battery screen.
- Cell voltages from six BMS DIDs (up to 192 cells), with a colour grid, a
  sorted cell-spread chart, deviation legend and the three weakest cells.
- Battery and charging self-tests with pass/warn/fail checks.
- Tire pressures and temperatures (TPMS); values are shown in bar (the psi branch exists but there is no UI switch yet).
- Always-on telemetry log, battery history (one snapshot per minute) and
  JSON/CSV export from the Logs & Export screen.
- Battery history chart for SOC, voltage, current and power: 1H/6H/24H/7D/ALL
  range chips, tap-or-drag point inspection, area + line styling, average and
  zero rules, min/avg/max footer, and the snapshot list as the text fallback.
- Tick-style state-of-charge gauge on Drive and a refined bidirectional
  power bar (regen/charge vs drive, quarter ticks, zero mark).
- Five bottom tabs: **Drive, Battery, Cells, Charging, Costs**. Drive merges
  the live summary with recent trips and a tire-pressure card; Trips is no
  longer a separate tab. A gear/settings button is available on every tab.
- Modern dark automotive theme: connection header, battery card, trip card,
  metric grid, tire card and recent trips. No big speed hero — this is an
  energy/trip app, not a dashboard to stare at while driving.
- Tariff lives in **Costs** as one collapsible card; charging lives in its own
  tab. Charging counters are now persisted in battery snapshots and shown with
  their last-known timestamp. Tire size can be selected (235/55 R19 or 255/45 R20) with a
  2.5 bar / 36 psi cold-pressure check per wheel.
- Battery screen explains the hierarchy (pack → modules → cells) and
  distinguishes the 800 V traction pack from the 12 V auxiliary battery
  (акумулатор) and its LDC charger. Cell detail lives only in the Cells tab.
- Nearby-only BLE discovery: max six adapters, 12-second scan, entries
  expire after five minutes.
- An original green "power-up mushroom" app icon with an EV bolt, inspired by
  classic power-up mushrooms rather than copied from any game character.
- English / Bulgarian UI with a Settings language switch (230 catalog keys, 197 translated; dynamic status/diagnostic/summary strings are still English).
- A local trip summary after every trip: when, where, distance, time,
  average/max speed, energy, cost and stop times.
- Hyundai BMS request `22 01 01` with multi-frame decode (SOC, pack voltage,
  current, temperatures, cell min/max, 12 V battery, isolation, inverter
  capacitor, derived power). The layout is validated against a real 62-byte
  Ioniq 5 capture; values stay labelled `candidate` until cluster-correlated.
- Fresh timestamps on every sample, so trip energy and cost integrate correctly.
- GPS speed fallback (only when OBD speed is absent or stale).
- Trip recording to SwiftData, raw-frame preservation, day/night tariff cost.
- Dashboard with provenance badges (an inline error line is planned; `TelemetryEngine.obdError` is published but not yet rendered).

Not validated yet:

- Cluster correlation of the BMS values (the capture decodes plausibly, but the
  app has not compared them side by side with the dashboard in one session).
- The standard bitmap on this car advertises only PIDs `01` and `20`, so no OBD
  speed/RPM/throttle is polled through functional `0100`. Speed uses GPS until a
  physical ECU request or Hyundai DID is confirmed.
- Background/locked-phone behaviour on the iPhone.

## Build

Open `IoniqDrive.xcodeproj` in Xcode, select the `IoniqDrive` scheme, choose your
iPhone 12 Pro, confirm the signing team, and Run.

This copy installs as **EV Info** with bundle identifier `com.evinfo.app`.
Change `CFBundleDisplayName` and `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`
(then run `xcodegen generate`) if you want a different name or a replacement
install.

`Package.swift` builds the core logic and tests only; it is not the deployable
iOS app target. The app target compiles all sources directly.

For design QA on the Simulator, Debug builds accept `-demo` (seeds a day of
sample battery history, live telemetry, cell voltages and tire data) and
`-demoRoute drive|battery|cells|charging|history` plus `-demoScrollBottom` to
open a screen directly. Release builds and the real BLE path are untouched.

Bluetooth and location usage descriptions are already in `Resources/Info.plist`.

## Sharing with friends

`Distribution/` contains an unsigned IPA plus guides for installing it with a
free Apple ID (Sideloadly / AltStore / SideStore). Free-account signatures last
7 days and allow 3 apps per device; TestFlight/App Store need the paid Apple
Developer Program. See `Distribution/README.md` for the full options and limits.

## Test

From the project root:

```sh
swift test --disable-sandbox
```

The `--disable-sandbox` flag is only needed when the shell is already sandboxed
(e.g. inside an agent). On a normal terminal `swift test` works.

Current result: 71 tests, 0 failures.
See `DESIGN.md` for the visual system and `OBD_PROTOCOL.md` for the PID map. See `TEST_RESULTS.md` for coverage.

## Electricity pricing

The default Bulgarian tariff profile is based on the supplied EVN invoice
(09.09.2026–08.10.2026):

- day energy: €0.09297/kWh
- night energy: €0.04103/kWh
- network charges: €0.03585/kWh
- 20% VAT, editable day/night rates

For an all-in bill model the app adds network and VAT rather than hard-coding
the €0.13267/kWh blended figure. All components are editable in Settings.

## Safety

The app is read-only. It does not send actuator, coding, or clear-diagnostic
commands. Raw responses are preserved so future decoders can be added without
losing trips.

## CarPlay

CarPlay remains a constrained platform: a normal app cannot draw an arbitrary
dashboard on the factory screen. The phone dashboard is the primary UI; see
`Sources/CarPlay/README.md`.
