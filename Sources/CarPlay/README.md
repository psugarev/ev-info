# CarPlay plan

Apple currently supports specific CarPlay app categories and requires the matching entitlement. The relevant category to investigate for a telemetry/mileage utility is Driving Task, but approval is controlled by Apple.

The app should therefore implement:
1. Full dashboard on iPhone.
2. Shared telemetry model.
3. A CarPlay scene only after entitlement is available.
4. Driving-safe, glanceable information rather than a continuously animated “video game” dashboard.

A true arbitrary custom speedometer on the factory CarPlay display is not something the app can assume is permitted. Apple documents CarPlay as template/entitlement based.
