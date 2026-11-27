# Test results

Last run: **2026-11-26**, macOS 27 SDK, Xcode 27.0, Swift 6.4 (Swift 5 language mode).

Command:

```sh
swift test --disable-sandbox
```

Result: **71 tests, 0 failures** (plus 0 swift-testing tests).

| Suite | Tests | Covers |
|---|---:|---|
| `BulgarianTariffEngineTests` | 8 | day/night boundary, VAT, zero/negative intervals |
| `EnergyCalculatorTests` | 12 | estimates, consumption, average speed, tariff split |
| `OBDResponseParserTests` | 38 | headers, ISO-TP, UDS `220101`/`220105`/`220111`/`22E011`, cell voltages, TPMS, VIN, odometer |
| `OBDSessionTests` | 4 | init sequence, discovery, BMS header switch + poll, timeout resync, failure states |
| `TripRecorderTests` | 3 | fresh-timestamp energy integration, regen, no-power path |
| `DiagnosticsTests` | 6 | battery/charging checks, trip summary, CSV/JSON export |

## Real capture used as a fixture

The `0100` response captured from the car (ELM327 v2.3, ISO 15765-4, `ATH1`):

```text
SEARCHING...
7EE 06 41 00 80 00 00 00
7EC 06 41 00 80 00 00 01
7EB 06 41 00 80 00 00 01
7EA 06 41 00 00 00 00 00
```

Decodes to `0x80000001`, i.e. only PID `0x01` and PID `0x20` are advertised by
the responding ECUs. No `0x0D` (speed), `0x0C` (RPM) or `0x11` (throttle) is
supported through functional `0100` on this gateway. Speed therefore falls back
to GPS unless a physical ECU request or a Hyundai DID exposes it.

Locked in by `testSupportedPIDsRealIoniqCapture`.

## Real BMS capture

`testBMSRealIoniqCapture` uses the full nine-frame response from the car
(2026-11-26) and asserts every decoded field, including the signed current and
the 693 V inverter capacitor reading. A second capture's out-of-range
inverter value is covered by a bounds-check test.

## Not yet verified

- **Real `220101` payload.** Validated against the 62-byte capture from the
  car: SOC 66.0 %, 692.3 V, 3.1 A, 13 °C max, 3.84 V cells, 13.8 V auxiliary.
  The app still labels the values `candidate` until they are correlated with
  the instrument cluster in one session.
- **BLE hardware path.** `BLETransport`, vLinker service discovery and writes
  require a device; unit tests use a fake transport.
- **iOS app build.** Verified with `xcodebuild` for the iOS Simulator
  (`BUILD SUCCEEDED`); it still needs a signed device build in Xcode on the M2
  before running on the iPhone 12 Pro.
- **Background behaviour.** Bluetooth/location background modes are configured,
  but a locked-phone trip has not been measured.
