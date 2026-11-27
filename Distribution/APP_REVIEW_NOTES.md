# EV Info — App Review notes

> Paste the block below into App Store Connect → App Review Information → Notes.
> Replace `<link>` with the hardware demo video before submitting.

---

EV Info is a read-only telemetry app for EVs. It needs a Bluetooth LE
ELM327-compatible OBD2 adapter (we use vLinker iCar Pro) plugged into the car's
OBD port.

**Review without hardware:** open Settings (gear icon on the Drive tab; the
other tabs have it in the top-right) and switch on **Demo mode**. The app then
shows a recorded sample session — battery, 192 cell voltages, charging, trips,
costs — so every screen can be evaluated. Demo mode is off by default, every
demo screen is labelled "DEMO", and demo data is never mixed with real vehicle
data. Alternatively, on a fresh install the Drive tab offers a "Use demo data"
button.

The app never sends actuator, coding or clear-diagnostic commands — it only
reads Mode 01 and UDS `22` data, plus GPS while a trip is being recorded (in the
foreground only). Bluetooth is the only background mode used. All data stays on
the device; no account is required and the app makes no network requests.

A short setup video showing the app pairing with the adapter on a physical
iPhone: `<link>` (a video, not a screen recording, because the app requires
hardware).

EV Info is not affiliated with or endorsed by Hyundai Motor Company. Hyundai and
Ioniq are trademarks of Hyundai Motor Company.
