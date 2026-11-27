# AGENTS.md

> **Starting a session? Read [`HANDOFF.md`](HANDOFF.md) first** — current state,
> open work, gotchas and the multi-agent branch/commit/PR conventions. Update it
> before you finish.

## Product goal
Build IoniqDrive as a read-only Hyundai Ioniq 5 telemetry/logger app.

## Hardware
- Development: MacBook Pro M2
- Runtime: iPhone 12 Pro
- Vehicle: Hyundai Ioniq 5 RWD, 2022
- Adapter: vLinker iCar Pro BLE 4.0

## Rules
1. Do not send control/actuator commands to the vehicle.
2. Preserve raw OBD/CAN/UDS responses for later decoding.
3. Never claim a PID is available until validated on the target vehicle.
4. Label derived values explicitly.
5. Prefer measured battery power over consumption estimates when a validated signal exists.
6. Use GPS for route/distance fallback, not as a silent replacement for OBD speed.
7. Keep tariff configuration editable; Bulgarian electricity prices change.
8. Treat CarPlay as a constrained UI, not an unrestricted second monitor.
