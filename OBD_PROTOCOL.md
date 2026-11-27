# OBD / UDS protocol notes

This file records what the app sends, what the car has been observed to return,
and which decoders are still candidates. It is the reference for future captures.

## Adapter configuration

| Command | Why |
|---|---|
| `ATZ` | reset |
| `ATE0` | echo off (the parser still tolerates an echo) |
| `ATL0` | no linefeeds |
| `ATS1` | spaces between bytes (the parser splits on whitespace) |
| `ATH1` | CAN headers on; needed to group ISO-TP frames per ECU |
| `ATAT1` | adaptive timing |
| `ATSP0` | auto protocol |
| `ATDPN` | read the detected protocol number (e.g. `A6`) |

The session switches headers explicitly:

- `ATSH7DF` — functional broadcast for Mode 01
- `ATSH7E4` — physical request to the BMS

## Standard support discovery

Request: `0100` (functional, `7DF`).

Captured response (2026-11-26, target car):

```text
SEARCHING...
7EE 06 41 00 80 00 00 00
7EC 06 41 00 80 00 00 01
7EB 06 41 00 80 00 00 01
7EA 06 41 00 00 00 00 00
```

Each line is `header length 41 00 bitmap[4]`. The union is **`0x80000001`**:

- bit 31 → PID `0x01` supported
- bit 0 → PID `0x20` supported (next range exists)

No `0x0D` (speed), `0x0C` (RPM), `0x11` (throttle) or `0x46` (ambient) is
advertised by any responder. Consequently the app polls no standard PIDs on this
gateway and speed falls back to GPS. This is not a bug in the bitmap parser; it
is what the car reports through functional `0100`.

Open questions for the next capture:

- Does a physical request (`ATSH7E0` + `0100`) reach an ECU with a richer bitmap?
- Does the gateway expose speed through a Hyundai DID instead?
- Which ECUs are at `7E0`–`7E7`? Only `7EA`–`7EE` answered here.

## Hyundai BMS — UDS `22 01 01`

Read-only service `0x22` (ReadDataByIdentifier), DID `0x0101`, physical header
`7E4`:

```text
ATSH7E4
220101
```

Positive response: `62 01 01 <59 data bytes>` from `7EC` (`7E4 + 8`), 62 bytes
total, carried over nine ISO-TP frames:

```text
7EC 10 3E 62 01 01 EF FB E7
7EC 21 EF 84 00 00 00 00 00
7EC 22 00 1F 1B 0B 0D 0C 0C
7EC 23 0D 0C 0D 0C 00 32 C0
7EC 24 A9 C0 0D 00 00 8A 00
7EC 25 05 F3 F4 00 05 C1 FD
7EC 26 00 04 1F E3 00 03 D6
7EC 27 9F 02 D7 0E 63 00 02
7EC 28 B5 00 00 00 00 0B B8
```

The app reassembles those into:

```text
62 01 01 | EF FB E7 EF 84 00 00 00 00 00 00 1F 1B 0B ...
         ^ data[0]
```

### Validated layout

Offsets are relative to the first data byte **after** `62 01 01`. The app
decodes this layout and labels the values `candidate` until they are correlated
with the instrument cluster in the same session.

| Data bytes | Meaning | Formula | Capture value |
|---|---|---|---|
| `data[4]` | dashboard SOC | raw / 2 | 66.0 % |
| `data[10..11]` | pack current | signed int16 / 10 | 3.1 A |
| `data[12..13]` | pack DC voltage | raw / 10 | 692.3 V |
| `data[14]` | max module temperature | signed int8 | 13 °C |
| `data[15]` | min module temperature | signed int8 | 12 °C |
| `data[16..20]` | module temperatures 1–5 | signed int8 | 12…13 °C |
| `data[22]` | battery inlet temperature | raw − 40 | 10 °C |
| `data[23]` | max cell voltage | raw / 50 | 3.84 V |
| `data[24]` | max cell number | raw | 169 |
| `data[25]` | min cell voltage | raw / 50 | 3.84 V |
| `data[26]` | min cell number | raw | 13 |
| `data[29]` | auxiliary 12 V battery | raw / 10 | 13.8 V |
| `data[51..52]` | inverter capacitor voltage | raw (0…1000 V) | 693 V |
| `data[57..58]` | isolation resistance | raw | 3000 kΩ |
| `data[9]` bit 0 | charging flag | bit | false |

This matches the OBDb `Hyundai-IONIQ-5` DID `0101` signal map. The current is
signed with **positive = discharge** in this app; some third-party apps invert
the sign and report discharge as negative. `data[4]` is the dashboard SOC;
Hyundai also exposes a separate BMS SOC (e.g. 65.0 % vs 65.5 %) elsewhere.

A second capture taken four minutes later decoded identically for SOC, voltage,
current, temperatures, cell voltages and cumulative energy; its inverter
capacitor field read `0x1999` (6553 V) and was rejected as out of range by the
parser. Keep that in mind if the inverter value ever looks implausible — the
signal is optional and bounds-checked.

### How to validate against the cluster

1. Capture `220101` while the car is awake.
2. At the same moment, record the instrument-cluster SOC %, pack voltage,
   current/power and battery temperature.
3. Compare with the table above. The BMS SOC is expected to differ slightly
   from the displayed SOC (the car exposes both; `data[4]` is the BMS value).
4. Add any new capture as a fixture in `Tests/OBDResponseParserTests.swift`.

Do not send actuator, coding or clear-diagnostic commands. Everything in this
app is read-only.

## VIN and odometer

These are useful identity/trip values that the other OBD apps also expose:

| Request | Header | Response | Decode |
|---|---|---|---|
| `22F190` | `7E2` → `7EA` | `62 F1 90` + 17 ASCII bytes | VIN |
| `22B002` | `7C6` → `7CE` | `62 B0 02` + data | odometer, 24-bit at data[6..8] |

Captured examples:

```text
62 F1 90 4B 4D 48 4B 4E 38 31 41 46 4E 55 30 33 30 36 37 31
        K  M  H  K  N  8  1  A  F  N  U  0  3  0  6  7  1   → VIN

62 B0 02 E0 00 00 00 FF B8 01 D5 25 ...
                          ^^^^^^^ 0x01D525 = 120101 km
```

`22B002` is polled every 10 s and `22F190` once per connection. The dashboard
shows the VIN and odometer under the OBD status line.

## Tire pressures — `22 C0 0B` (7A0 → 7A8)

| Data bytes | Meaning | Formula | Capture |
|---|---|---|---|
| `data[4]` / `data[5]` | front left pressure / temp | raw / 5 psi, raw − 50 °C | 37.6 psi, 11 °C |
| `data[9]` / `data[10]` | front right | same | 37.6 psi, 10 °C |
| `data[14]` / `data[15]` | rear left | same | 37.8 psi, 11 °C |
| `data[19]` / `data[20]` | rear right | same | 37.8 psi, 11 °C |

`0xFF`/`0` means the sensor is not present. The app converts psi to bar for
display and offers a bar/psi toggle.

## Cell voltages — `220102/03/04/0A/0B/0C`

Six requests, 32 cells each:

| DID | Cells |
|---|---|
| `220102` | 1–32 |
| `220103` | 33–64 |
| `220104` | 65–96 |
| `22010A` | 97–128 |
| `22010B` | 129–160 |
| `22010C` | 161–192 |

Each payload starts with `62 01 <did>`, then four status bytes, then 32 cell
bytes at `data[4..35]`; voltage = raw / 50. `0xFF` marks an unpopulated cell
and is skipped. The app polls each DID every 30 s and fills a 192-slot grid.

## Battery health — `22 01 05` (7E4 → 7EC)

43-byte payload. Offsets are data-relative (after `62 01 05`).

| Data bytes | Meaning | Formula | Capture |
|---|---|---|---|
| `data[9..15]` | module temperatures B06–B12 | signed int8 | 12…13 °C |
| `data[25..26]` | State of Health | raw / 10 | 95.5 % |
| `data[28..29]` | remaining energy | raw × 2 / 1000 | 39.256 kWh |
| `data[31]` | display SOC | raw / 2 | 65.5 % |

Captured (17:10):

```text
62 01 05 FF FB 74 0F 01 2C 01 01 2C 0D 0C 0D 0C 0D 0D 0C
5C E6 62 D4 00 00 50 0C 00 03 BB 60 4C AC 00 83 ...
                          ^^^^^ SoH     ^^^^^ energy  ^^ SOC
```

## Charging counters — `22 01 11` (7E4 → 7EC)

| Data bytes | Meaning | Formula | Capture |
|---|---|---|---|
| `data[4..7]` | AC charging sessions | uint32 | 456 |
| `data[8..11]` | DC charging sessions | uint32 | 209 |
| `data[12..15]` | AC energy total | uint32 kWh | 12 529 kWh |
| `data[16..19]` | DC energy total | uint32 kWh | 2 622 kWh |

## 12 V / LDC — `22 E0 11` (7E5 → 7ED)

| Data bytes | Meaning | Formula | Capture |
|---|---|---|---|
| `data[9]` | LDC temperature | raw − 100 | 15 °C |
| `data[10..11]` | LDC output voltage | raw / 1000 | 14.94 V |
| `data[12..13]` | LDC output current | raw × 10 / 1000 | 27.3 A |
| `data[14..15]` | LDC input voltage | raw / 10 | 693.7 V |
| `data[18..19]` | auxiliary battery current | raw / 100 − 327 | 11.86 A |
| `data[20]` | auxiliary battery SOC | raw | 89 % |
| `data[21..22]` | auxiliary battery voltage | raw / 1000 + 6 | ~14.7 V |

The BMS also reports a 12 V value in `220101 data[29]` (13.8–14.3 V); the two
measurements can differ slightly. The dashboard uses the `220101` value and the
Battery screen shows both.

## ISO-TP framing quick reference

| PCI high nibble | Meaning |
|---|---|
| `0` | single frame; low nibble = length |
| `1` | first frame; 12-bit length in low nibble + next byte |
| `2` | consecutive frame; low nibble = sequence number |
| `3` | flow control (ignored by the parser) |

With `ATH1` the ELM prints the CAN header before the PCI bytes. With headers off
it may print `0: …`, `1: …` lines instead; both forms are supported.
