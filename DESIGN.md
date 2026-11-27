# Design system

Source: `ui-ux-pro-max` design-system search for a mobile EV telemetry
dashboard, then adapted to native SwiftUI/HIG. The result is a dark,
data-dense automotive dashboard rather than a marketing page.

## Direction

- **Style:** Dark Mode (OLED) + Data-Dense Dashboard.
- **Mood:** precise, calm, night-driving, instrument-cluster inspired.
- **Rules:** near-black surfaces, one cyan accent for live data, green for
  healthy/regen, amber for warnings, red only for faults. No gradients used as
  decoration; the only glow is a subtle cyan halo around the speed ring.
- **Density:** compact cards, 4/8 pt rhythm, one hero number (speed).

## Tokens (`Sources/UI/Theme.swift`)

| Token | Value | Use |
|---|---|---|
| `background` | `#06080D` | app background |
| `backgroundElevated` | `#0B1018` | bars / sheets |
| `surface` | `#111722` | cards |
| `surfaceElevated` | `#17202E` | nested tiles |
| `border` | `#223044` | 1 pt card borders |
| `textPrimary` | `#F1F5F9` | values |
| `textSecondary` | `#94A3B8` | labels |
| `textTertiary` | `#64748B` | captions |
| `cyan` | `#22D3EE` | live speed/power, selected tab |
| `green` | `#34D399` | healthy battery, regen |
| `amber` | `#FBBF24` | warnings / no signal |
| `red` | `#F87171` | faults, stop |
| `violet` | `#A78BFA` | odometer |

- Card radius: **24 pt** continuous.
- Spacing: **4 / 8 / 12 / 16 / 24 / 32**.
- Touch targets: **44 pt minimum**.
- Typography: native **SF Pro Rounded** for numbers/titles, **SF Mono /
  monospaced digits** for live data. No custom font download.
- Dynamic Type: all text uses semantic/relative sizes where practical; hero
  speed uses `minimumScaleFactor`.

## Screen structure

- **Drive:** connection header, battery card, trip card with an inline
  Start/Stop action, 2×2 metric grid, a tire-pressure card and recent trips.
  There is deliberately no large speed hero; the app is energy/trip focused.
  Settings is reachable from every tab.
- **Charging:** live charging state/power, lifetime AC/DC counters (persisted
  with a last-known timestamp) and the charging test.
- **Costs:** total cost/energy, one collapsible electricity-tariff card and the
  trip cost list. Tariff is never shown on Drive.
- **Battery:** a summary card with an (i) button opening a "Battery explained"
  sheet, an info card explaining pack → modules → cells, and collapsible
  groups (Health, HV Pack, 12 V battery & DC-DC, Diagnostics, More). Cell
  voltages are not duplicated here; charging and costs have their own tabs.
- **Cells:** an "About the BMS" info card, a read/max/min/delta summary, a
  sorted cell-spread chart (weakest → strongest, coloured by deviation from the
  strongest cell) with a legend and the three weakest cells, then the 192-cell
  grid.
- **Tires:** 2×2 cards, bar display (no psi switch yet), temperature, tire-size picker and a
  cold-pressure check against 2.5 bar (36 psi) with a ±0.2 bar tolerance.
- **Trips:** part of Drive (recent trips + All trips → list/detail with local
  summary).

## Charts

- **Battery History** is a scrollable instrument card, not a list:
  - time-range chips (1H / 6H / 24H / 7D / ALL) that re-filter the series;
  - segmented metric picker (SOC, Voltage, Current, Power);
  - iOS 17 `chartXSelection` — tap or drag the plot to inspect a point, with a
    rule line, a highlighted dot and a value annotation;
  - area fill at 28 % → 2 % opacity, 2 pt catmull-rom line in the metric
    colour, a dashed average rule, and a zero rule for signed current/power;
  - padded y-domain per metric (flat series are not magnified into fake noise),
    monospaced 9 pt axes, and a "now" dot at the newest sample;
  - min / average / max footer and a latest-values tile grid;
  - the snapshot list stays below the chart as the text/table fallback and is
    capped to 30 rows until "Show all" is tapped.
- Charts are downsampled to ≤ 320 points (`displayPoints`) so a week of
  one-minute snapshots stays smooth; the underlying list is capped at 20 000
  rows.
- **Cells spread chart**: 192 `BarMark`s sorted by voltage, coloured by the
  same ≤10 / 10–30 / >30 mV bands as the grid, with a legend, weakest-cell
  chips and a y-domain padded to the observed min/max.

## Gauges

- The Drive battery card uses a tick gauge (`SOCGauge`, `Theme.swift`): 45
  radial ticks in a 270° sweep, every fifth tick longer, filled with the
  battery colour (green / amber / red by SOC), plus a live dot at the leading
  tick. No continuous animation — the value jumps on the one-minute BMS poll.
- The bidirectional power bar keeps flat colour (no decoration), now with
  quarter ticks, a zero mark, and REGEN/POWER direction labels.

## Accessibility

- Colour is never the only signal: values/labels are always present.
- Contrast: primary text on near-black > 7:1; secondary > 4.5:1.
- There is no speed hero (removed by request); speed is a compact contextual row and
  still needs a source chip once GPS fallback is surfaced.
- Reduced motion: animations are short opacity/trim changes; no continuous
  motion. Respect `accessibilityReduceMotion` in a later pass.
- Tab bar and toolbar stay inside safe areas; scroll content gets bottom inset
  for the floating action and tab bar.

## Localization

- `Resources/Localizable.xcstrings` with **English** and **Bulgarian**
  (237 keys, 204 translated).
- Settings → App → Language (English / Български).
- `@AppStorage("appLanguage")` drives `.environment(\.locale, …)` at the root.
- Catalog keys cover tabs, dashboard, battery, cells, tires, trips, logs, settings
  and diagnostics. Dynamic values (BLE statuses, diagnostic details, geocoded
  trip summaries) are still English and are the next localization pass.

## Deliberately deferred

- Custom car silhouette/logo and an animated gauge sweep (the tick gauge
  animates only value changes, not a continuous needle sweep).
- CarPlay: requires an Apple CarPlay entitlement and template-based UI.
- Light mode: the app is dark-only by design.


## App icon

`Resources/Assets.xcassets/AppIcon.appiconset` — an original green power-up
mushroom with cream spots and a dark EV bolt on the stem, on a deep navy
gradient. Generated as a full iPhone/iPad size set plus 1024 marketing icon;
iOS applies the rounded mask. It is an original motif, not Nintendo artwork.
