# Architecture

```text
vLinker BLE
   ↓ notify / write
BLETransport (CoreBluetooth, known UART profiles)
   ↓ OBDTransport
OBDSession
   ├── command queue (one request in flight, 64-deep, de-duplicated)
   ├── timeout + resync ("\r" flush, late replies discarded)
   ├── header manager (7DF functional ↔ 7E4 BMS)
   ├── discovery (0100 / 0120 / 0140 bitmaps)
   ├── polling (per-PID timers, coalesced)
   └── decoding
         ├── OBDResponseParser (ISO-TP reassembly, Mode 01, UDS 22 01 01)
         └── TelemetrySample (fresh timestamp on every publish)
   ↓ sampleUpdates
TelemetryEngine ──────────────── Dashboard
   ├── speed fallback from GPS (only when OBD is absent/stale)
   ├── provenance labels (standard / hyundaiExtended / derived / gps)
   └── OBD status + error line
   ↓
TripRecorder → SwiftData (trips + raw frames)
TelemetryStore → SwiftData (telemetry log, battery history, test reports)
   └── ExportService → JSON / CSV files
   └── EnergyCalculator → BulgarianTariffEngine → cost
```

## UI

`RootTabView` holds five sections. `Theme` defines the dark palette, card
shape and metric typography; `DashboardView` is the hero speed/battery screen.
`Resources/Localizable.xcstrings` carries English and Bulgarian strings, and
`@AppStorage("appLanguage")` drives the root locale.

## Transport abstraction

`OBDTransport` is a small protocol (`isConnected`, connect/data publishers,
`send`). `BLETransport` conforms in the app; tests inject a fake transport. This
keeps `OBDSession` free of CoreBluetooth and makes the init/discovery/decoding
flow testable without hardware.

## Request lifecycle

1. One command is written at a time; the ELM327 is half-duplex.
2. The session waits for the `>` prompt, not for a BLE packet boundary.
3. A watchdog fires on timeout: the pending command is dropped, the buffer is
   cleared, `\r` is sent to resynchronise, and late bytes are discarded until
   the next prompt. Previously a late reply could complete the following
   command with stale data.
4. Duplicate poll requests are not queued again while one is pending; the queue
   is capped at 64 entries so a slow adapter cannot grow it without bound.
5. Header changes are queued immediately before the request that needs them.
   Standard Mode 01 requests use `7DF`; the BMS uses `7E4`.

## Can framing

`OBDResponseParser.payloads(from:)` reassembles:

- single frames (`7E8 03 41 0D 64`),
- ISO-TP first + consecutive frames grouped per CAN header
  (`7EC 10 0E …`, `7EC 21 …`, `7EC 22 …`),
- ELM's numbered multi-frame form (`0: …`, `1: …`),
- bare payloads from adapters that strip the PCI byte.

No parser assumes a fixed byte offset into the raw text; all decoders search the
reassembled payload for their service prefix.

## Data provenance

Every metric has a source enum:

- `obdStandard` — validated Mode 01 response
- `hyundaiExtended` — Hyundai BMS/UDS, still a candidate until cluster-correlated
- `gps` — CoreLocation fallback
- `derived` — calculated (power = V × I, consumption)
- `unavailable` — no signal

The dashboard shows `candidate` for `hyundaiExtended`/`derived` values and
`no signal` when nothing has been decoded.

## Polling groups

- FAST: vehicle speed (`010D`, 0.2 s)
- MEDIUM: BMS `220101` (1 s), throttle (`0111`, 0.5 s), RPM (`010C`, 1 s)
- SLOW: ambient temperature (`0146`, 10 s)
- HEALTH: SoH/remaining energy (`220105`, 10 s), 12 V/LDC (`22E011`, 10 s),
  charging counters (`220111`, 60 s), odometer (`22B002`, 10 s), VIN once

Only PIDs advertised by the vehicle's support bitmap are started. The BMS poll
is always started after discovery so its raw response can be validated even if
the standard bitmap is nearly empty.

## Energy calculation

When battery power exists, integrate signed power over time:

```text
energy_kWh += power_kW × deltaTime_hours
```

Positive power discharges; negative regen reduces net energy. Cost is charged
only on positive energy increments, split at day/night boundaries.

When no validated power signal exists, fall back to distance × reference
consumption and label the result as derived.

## Raw preservation

Every completed ELM response is emitted on `rawResponses` and persisted as a
`RawOBDFrame`, including init and discovery frames. Writes are batched (every 25
frames plus on trip stop) instead of saving each frame individually.
