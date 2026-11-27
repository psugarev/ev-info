# OBD research plan

## Generic OBD-II baseline
Implement discovery first:
- 01 00 supported PIDs 01–20
- 01 20 supported PIDs 21–40
- 01 40 supported PIDs 41–60
- 01 0D vehicle speed

Many gasoline-engine PIDs are irrelevant to a BEV. Do not display engine RPM, coolant, fuel level, or fuel-rate values as if they were meaningful Ioniq 5 metrics merely because an ECU answers them.

## Hyundai-specific target metrics
After baseline connectivity works, capture and investigate:
- HV battery SOC
- pack voltage
- pack current
- battery power
- battery temperatures
- cell min/max voltage and delta, if exposed
- motor speed/RPM
- inverter temperature
- charging state
- odometer
- regen/brake energy
- DC/AC charging power

Exact PIDs depend on ECU, model year, gateway/protocol and adapter behavior. Add only validated definitions.

## Development workflow
1. Connect BLE.
2. Log raw ELM327 responses.
3. Determine protocol and ECU addressing.
4. Capture responses while driving/charging.
5. Correlate candidate values with dashboard values.
6. Add a parser and unit conversion.
7. Add automated fixture tests using the captured response.
8. Only then expose the metric in the UI.

## Status 2026-11-26

- `0100` captured on the target car (functional `7DF`): the responding ECUs
  advertise only PID `0x01` and `0x20` (`0x80000001`). Speed/RPM/throttle are not
  available through functional Mode 01 on this gateway.
- `22 01 01` (UDS ReadDataByIdentifier, DID `0101`) is implemented and its
  62-byte payload layout has been validated against a real capture: SOC 66 %,
  692.3 V, 3.1 A, 13 °C max, 3.84 V cell min/max, 13.8 V auxiliary, 3000 kOhm
  isolation. The app still labels the values `candidate` until they are
  correlated with the instrument cluster in one session.
- Next: capture a physical `0100` on `7E0`–`7E7`, and the full `220101` reply at
  idle, under load, and during regen.
