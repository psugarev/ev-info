# Data model

## TripRecord (SwiftData)
- id UUID
- startDate / endDate
- distanceKm Double
- durationSeconds Double
- averageSpeedKmh Double
- maxSpeedKmh Double
- energyKWh Double?
- consumptionKWhPer100Km Double?
- costEUR Double?
- stopCount Int? / stopSummary String?
- start/end latitude/longitude Double?
- summary String? (local trip summary)
- encodedPolyline String? (reserved; route export not implemented yet)

## RawOBDFrame (SwiftData)
- id UUID
- tripID UUID? (nil for frames outside a trip)
- timestamp Date
- request String
- response String (unmodified adapter text, including prompt)

Raw frames are preserved so future Hyundai-specific decoders can be added
without losing old trips.

## TelemetrySample (value type, not persisted per-sample)
- id / timestamp (timestamp is the time the sample was built, not session start)
- speedKmh — Mode 01 `010D`
- gpsSpeedKmh — CoreLocation fallback
- socPercent — Hyundai `220101` dashboard SOC (candidate)
- batteryVoltageV — Hyundai `220101` candidate
- batteryCurrentA — Hyundai `220101` candidate (positive = discharge)
- batteryPowerKW — derived `V × I / 1000`
- batteryTemperatureC / batteryMinTemperatureC / batteryInletTemperatureC — Hyundai `220101` candidates
- cellVoltageMaxV / cellVoltageMinV — Hyundai `220101` candidates
- auxiliaryVoltageV — Hyundai `220101` 12 V candidate
- auxiliaryCurrentA / auxiliarySOCPercent — `22E011` candidates
- sohPercent / remainingEnergyKWh — `220105` candidates
- normalChargeCount / quickChargeCount — `220111`
- normalChargeEnergyKWh / quickChargeEnergyKWh — `220111`
- ldcTemperatureC / ldcOutputVoltageV / ldcOutputCurrentA — `22E011` candidates
- bmsRawPayload — hex of the reassembled UDS payload, for validation
- motorRPM — Mode 01 `010C` (may be meaningless on a BEV)
- acceleratorPercent — Mode 01 `0111`
- ambientTemperatureC — Mode 01 `0146`
- brakePercent — reserved, not decoded
- odometerKm — UDS 22B002 on 7C6 (km)
- tirePressuresBar / tireTemperaturesC — TPMS from `22C00B`
- latitude / longitude — GPS
- rawPayload — reserved debug echo

## Provenance
`MetricSource`: `obdStandard`, `hyundaiExtended`, `gps`, `derived`,
`unavailable`. The dashboard labels `hyundaiExtended` and `derived` values as
`candidate`; it never presents a candidate as a validated measurement.

## TelemetryLogRecord
Always-on compact log (one row per second while connected): timestamp, speed,
SOC, pack voltage/current/power, cell min/max, temperatures, 12 V, SoH,
odometer, coordinates.

## BatterySnapshot
One row per minute: SOC, SoH, pack voltage/current/power, cell min/max,
temperatures, 12 V, remaining energy. Used for the history chart.

## DiagnosticReport
Saved battery/charging test: date, kind, pass/warn/fail, title, summary and a
JSON list of individual checks.

## TripSummary
Read-only DTO derived from `TripRecord` for list views and exports.
