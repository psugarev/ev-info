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
swift test --disable-sandbox            # 94 tests, core logic (macOS)
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
- CI (`.github/workflows/ci.yml`) runs on every PR and on `main`: `swift test`, then
  XcodeGen + Release build for `generic/platform=iOS Simulator`, a project-sync check
  (`xcodegen generate` must not change the committed project), and bundle assertions
  (privacy manifest present and valid, bundle id / display name / export-compliance,
  `en.lproj` + `bg.lproj`). Runs on `macos-26` (Xcode 26.x), ~6–10 min per PR.
- CI pins **XcodeGen 2.49.0** (env `XCODEGEN_VERSION` in the workflow) so the
  project-sync check is deterministic. If you bump XcodeGen locally, bump that pin in
  the same PR and commit the regenerated project.

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

## Open work

The backlog lives in GitHub Issues (labels `P0` / `P1` / `P2`, `area:*`):
https://github.com/psugarev/ev-info/issues — this list is a snapshot, the issues
are the source of truth.

| # | Task | Priority |
|---|---|---|
| [#5](https://github.com/psugarev/ev-info/issues/5) | Connect flow: init progress text + real-device verification | P0 |
| [#3](https://github.com/psugarev/ev-info/issues/3) | Localise dynamic strings, purge stale keys | P0 |
| [#2](https://github.com/psugarev/ev-info/issues/2) | Screenshots in demo mode | P0 |
| [#12](https://github.com/psugarev/ev-info/issues/12) | App Store Connect admin (owner task, not code) | P0 |
| [#4](https://github.com/psugarev/ev-info/issues/4) | Dynamic Type, hit targets, Reduce Motion | P1 |
| [#7](https://github.com/psugarev/ev-info/issues/7) | Charge-session log with cost | P1 |
| [#8](https://github.com/psugarev/ev-info/issues/8) | Read-only DTC scan | P1 |
| [#9](https://github.com/psugarev/ev-info/issues/9) | Units setting | P1 |
| [#10](https://github.com/psugarev/ev-info/issues/10) | Per-trip export and backup/restore | P1 |
| [#11](https://github.com/psugarev/ev-info/issues/11) | Colour semantics, onboarding, daylight theme | P1 |

## How to continue (every agent, every session)

1. `git clone https://github.com/psugarev/ev-info && cd ev-info && git pull`; read this file and `AGENTS.md`.
2. Pick an issue; **comment "claiming" on it** and add an `agent:*` label so two agents never take the same task.
3. `git switch -c agent/<agent-name>/<topic>` from an up-to-date `main`.
4. Work in small commits (`<type>: <description>` + `Agent:` trailer). Run `swift test --disable-sandbox` and a Release build.
5. `git push -u origin <branch>` and open a PR with `Closes #<issue>`; state what was verified and what was not (e.g. "not tested on device").
6. In the same PR, update this file: tick/remove the finished item, add new gotchas, append a Session-log row.
7. The owner reviews and merges. Never push to `main` directly.

## Known gaps / gotchas

- **Never validated on a real car this pass**: auto-reconnect via
  `retrievePeripherals`, Bluetooth denial flow, stale threshold (3 s vs the 1 s BMS poll), background behaviour.
- Demo mode shows no speed on purpose (OBD speed is not validated, rule 3).
- `LocationManager` is foreground-only; re-adding the `location` background mode
  needs on-device validation first (Guideline 2.5.4).
- `TripRecorder.swift:266/272` has two pre-existing actor-isolation warnings.
- Retention purges raw frames/telemetry/snapshots/reports but keeps trip summaries.
- Cells: the six blocks follow the six BMS cell DIDs; the real physical module
  boundaries are not exposed over OBD, so the UI says "module grouping follows
  the six BMS cell blocks". Thresholds (≤10 / 10–30 / >30 mV below the strongest
  cell) live in `CellAnalysis` — change them there, not in the view.
- Cells screenshot harness (Debug only): `-demoScrollModule 2` scrolls to that
  block, `-demoCell 42` opens the detail sheet; combine with `-demo -demoRoute cells`.
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
| 2026-11-27 | Claude (deepseek-flash) | `agent/lead/cell-grid-redesign` | Issue #6: six labelled 32-cell module blocks (read count, min/max/Δ, BALANCED/WATCH/DRIFT chip), strongest/weakest ring per block, weakest-cell ranking card, tap-to-cell detail sheet, threshold legend with band counts, testable `CellAnalysis` + 10 tests, EN/BG strings, screenshot harness | 94 tests, Release + Debug build, simulator EN + BG screenshots |
| 2026-11-27 | Claude (deepseek-flash) | `agent/lead/ci-workflow` | Issue #16: GitHub Actions CI — `swift test` + XcodeGen/Release build, project-sync guard, bundle checks (privacy manifest, identity, lproj), pinned XcodeGen 2.49.0, README badge | workflow green on its own PR and on `main` |
