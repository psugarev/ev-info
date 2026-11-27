# App Store screenshots

Captured from **Demo mode** on the iOS simulator — no car, no adapter, no device
frames and no baked-in marketing text (App Store Guideline 2.3.3).

## Sizes

| Folder | Device class | Pixels | App Store slot |
|---|---|---|---|
| `69/` | iPhone 18 Pro Max | 1320 × 2868 | 6.9-inch iPhone |
| `65/` | iPhone 11 Pro Max | 1242 × 2688 | 6.5-inch iPhone |

Each size has two language sets: `en/` (English) and `bg/` (Български).

## Order (must match the listing)

| File | Screen |
|---|---|
| `01-drive.jpg` | Drive — SOC gauge, pack power, trip card, tires |
| `02-battery.jpg` | Battery — SoH, remaining energy, 12 V / LDC, diagnostics |
| `03-cells.jpg` | Cells — six module blocks, weakest-cell ranking |
| `04-charging.jpg` | Charging — live power, AC/DC lifetime counters |
| `05-costs.jpg` | Costs — total cost/energy, tariff, trip list |
| `06-trip.jpg` | Trip detail — local summary, distance, energy, cost |

JPEG, quality 88. PNG captures are converted with `sips`; App Store Connect
accepts either format, and JPEG keeps the repository small.

## Regenerate

```bash
bash scripts/capture-appstore-screenshots.sh
```

The script builds the Debug simulator app, boots the two devices (creating the
6.5-inch one if needed), overrides the status bar to 9:41 / full battery and
captures each route with `-demo -demoRoute … -appLanguage en|bg`, then verifies
the pixel size of every file. It takes roughly 10 minutes.

Screens are only presentable because demo mode seeds sample trips (Costs and
Trip detail) in addition to the 24 h battery history. Demo data is labelled
`DEMO` in the UI and never mixes with real vehicle data.

## When to re-capture

- Any visible UI change on these six screens.
- A change to the demo seed data (numbers, trips, cell outliers).
- A new iOS version changes the status bar or system typography.
