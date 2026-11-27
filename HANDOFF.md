# HANDOFF — read this first

Current state of **EV Info** (`com.evinfo.app`, repo folder `IoniqDrive2`) for any
AI agent or human picking the work up. Keep this file current: update it at the
end of every session (see "Session log" at the bottom).

**Repo:** https://github.com/psugarev/ev-info (private, default branch `main`).
Clone, then follow "Build & test" below.

## What the app is

Read-only SwiftUI / SwiftData / CoreBluetooth / CoreLocation telemetry app for a
Hyundai Ioniq 5 (E-GMP) via a BLE ELM327 adapter (vLinker iCar Pro). Battery,
192 cell voltages, charging, trips, Bulgarian day/night tariff costs. iPhone
only, iOS 17.6+, English + Bulgarian. Non-negotiable rules are in `AGENTS.md`
(never send control/actuator commands, preserve raw frames, label derived data,
never claim a PID is validated before it is).

## Build & test

```bash
xcodegen generate                       # project.yml is the source of truth
swift test --disable-sandbox            # 84 tests, core logic (macOS)
xcodebuild -project IoniqDrive.xcodeproj -scheme IoniqDrive \
  -configuration Release -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

- Never hand-edit `Resources/Info.plist`; edit `project.yml` and regenerate.
- `Package.swift` compiles `Sources/` as a library (all but `App/IoniqDriveApp.swift`)
  so new files must build on macOS too (guard UIKit with `#if os(iOS)`).
- Debug-only harness: launch args `-demo`, `-demoRoute drive|battery|cells|charging|history`.
  You can also pass NSUserDefaults overrides, e.g. `-disclaimerAccepted YES -demoModeEnabled YES`.
- Simulator cold start shows a blank launch screen for ~10 s (dyld cost, not app code).

## Where things are

| Area | Files |
|---|---|
| App entry, demo sync, disclaimer, storage banner | `Sources/App/IoniqDriveApp.swift`, `DemoData.swift`, `AppLog.swift` |
| BLE (lazy central, remembered adapter, demo connection) | `Sources/Bluetooth/BLETransport.swift` |
| OBD/ELM327 engine, PIDs, parsing | `Sources/OBD/*` (see `OBD_PROTOCOL.md`) |
| Live state, freshness, demo | `Sources/Telemetry/TelemetryEngine.swift` |
| Persistence: schema/migrations, retention, export | `Sources/Storage/AppSchema.swift`, `DataRetention.swift`, `ExportService.swift` |
| UI | `Sources/UI/*` (`DashboardView`, `SettingsView`, `DisclaimerView`, `LogsView`, …) |
| Localisation | `Resources/Localizable.xcstrings`, `Resources/InfoPlist.xcstrings` |
| App Store material | `APP_STORE_AUDIT.md` (the plan), `Distribution/PRIVACY_POLICY.md`, `Distribution/APP_REVIEW_NOTES.md` |

## What has been done

Full table in `APP_STORE_AUDIT.md` §2b. Summary: user-facing Demo mode, "—" for
missing values, stale badge, connect empty state, provenance badges, speed row
with source chip, lazy Bluetooth + auto-reconnect, foreground-only location
(background `location` mode removed), retention / cascade delete / delete-all,
off-main export with range, SwiftData `SchemaV1` + migration plan (no `try!`,
visible storage-failure banner), first-run disclaimer, 57 BG strings +
Info.plist BG strings, contrast fix, `os.Logger`. Verified: 84 tests pass,
Release + Debug builds succeed, simulator run seen for disclaimer and Drive/demo.

## Open work (priority order)

1. **Screenshots in demo mode**, 6.9" and 6.5" (shot list: Audit Appendix C).
2. **Localise dynamic strings** (BLE status text, `VehicleDiagnostics`, `TripSummaryGenerator`, chart titles); purge stale `Localizable` keys (build in Xcode marks them stale).
3. **Dynamic Type**: replace ~55 hard-coded font sizes with a `Theme.font` system, min 12 pt; sub-44 pt targets; Reduce Motion.
4. Connect-step progress text during `ATZ` init; verify auto-reconnect on a real device.
5. **Cell grid redesign** (six 32-cell module blocks, min/max, weakest-cell ranking).
6. P1 features: charge-session log with cost, read-only DTC scan (Mode 03/07/0A, never clear), units setting, per-trip CSV/GPX export.
7. Colour-semantics cleanup, replace hard-coded `.blue/.green/…` in TripHistory, Logs, BatteryHistory, CellVoltage; onboarding pages; daylight theme.
8. Not repo work: host privacy policy, age rating, EU DSA trader status, hardware demo video, fill placeholders in `Distribution/*`.

## Known gaps / gotchas

- **Never validated on a real car this pass**: auto-reconnect via
  `retrievePeripherals`, Bluetooth denial flow, stale threshold (3 s vs the 1 s BMS poll), background behaviour.
- Demo mode shows no speed on purpose (OBD speed is not validated, rule 3).
- `LocationManager` is foreground-only; re-adding the `location` background mode
  needs on-device validation first (Guideline 2.5.4).
- `TripRecorder.swift:266/272` has two pre-existing actor-isolation warnings.
- Retention purges raw frames/telemetry/snapshots/reports but keeps trip summaries.
- Any model change needs a new `VersionedSchema` + migration stage in `AppSchema.swift`.

## Working agreement for multiple agents (traceability)

1. **One task = one branch**: `agent/<agent-name>/<short-topic>` (e.g. `agent/claude/dynamic-type`). Never commit to `main` directly.
2. **One PR per task**, description = what/why/how verified, linked to the audit item or issue.
3. **Commit format**: `<type>: <description>` (feat, fix, refactor, docs, test, chore, perf, ci), plus trailers:
   `Agent: <tool and model>` and, if relevant, `Task: <issue or audit id>`.
4. **Before opening a PR**: `swift test --disable-sandbox` green and a Release build; say in the PR if either was not run.
5. **End of session**: append a row to the log below and update "Open work" and "Known gaps". Do not delete earlier rows.
6. Record decisions that change behaviour in the PR/issue, not only in chat.

## Session log

| Date | Agent | Branch / commit | Summary | Verified |
|---|---|---|---|---|
| 2026-11-26 | (earlier agent) | pre-repo | Initial audit `APP_STORE_AUDIT.md`; privacy manifest, Info.plist purpose strings, iPhone-only, export names | Release build, 71 tests |
| 2026-11-27 | Claude (Sonnet 5.5) | `main` @ 42ab1db | Implemented audit blockers + P0/high items (see §2b of the audit); added 13 tests, HANDOFF.md | 84 tests, Release + Debug build, simulator spot-check |
| 2026-11-27 | Claude (Sonnet 5.5) | `agent/claude/handoff-repo-link` | Created private repo `psugarev/ev-info`, initial import, recorded repo URL; installed `gh` via Homebrew | docs only |
