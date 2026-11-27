# App Store Connect — submission kit

Everything that can be prepared outside App Store Connect lives here. Items marked
**OWNER** need a login to App Store Connect / Apple Developer and cannot be done
from the repository.

## Audit §7 status

| Item | Status | Where |
|---|---|---|
| Privacy manifest | ✅ in bundle | `Resources/PrivacyInfo.xcprivacy`, asserted in CI |
| Export compliance | ✅ `ITSAppUsesNonExemptEncryption = false` | `project.yml` |
| App category | ✅ declaration; **OWNER** picks it in ASC | see “Category” below |
| iPhone-only | ✅ `TARGETED_DEVICE_FAMILY = 1` | `project.yml` |
| Privacy policy URL | ✅ page written, hosting enabled | https://psugarev.github.io/ev-info/privacy.html |
| Support URL | ✅ page written, hosting enabled | https://psugarev.github.io/ev-info/support.html |
| Screenshots 6.9" + 6.5" | ✅ 24 files, EN + BG | `Distribution/screenshots/` |
| Age rating 4+ | ⏳ **OWNER** answers the questionnaire | answers below |
| EU DSA trader status | ⏳ **OWNER** | steps below |
| App Review notes | ✅ drafted | `Distribution/APP_REVIEW_NOTES.md` |
| Hardware demo video | ⏳ **OWNER** records it | script below, link goes into review notes |
| Privacy label (“Data Not Collected”) | ✅ verified: no networking/analytics | answers below |
| Pricing / IAP | ✅ v1 free, no IAP | decision below; Pro unlock tracked separately |

## Listing copy (paste into ASC)

**Name (≤30):** `EV Info — EV battery & OBD2` (26)
**Subtitle (≤30):** `Battery, cells, charging, cost` (30)
**Promotional text (≤170):**
`See what your EV's BMS is really doing: state of health, all 192 cell voltages, charging power, tires, trips and real energy cost — computed on your iPhone, nothing uploaded.`

**Keywords (≤100 bytes, no spaces):**
`OBD2,ELM327,EV,battery,SoH,cell voltage,charging,trip,cost,telemetry,E-GMP`

**Description:**

> EV Info reads your car over an ELM327-compatible Bluetooth OBD2 adapter and shows
> what the dashboard hides: the state of health of the traction battery, the voltage of
> every one of the 192 cells in six module blocks, pack and 12 V behaviour, charging
> power and lifetime AC/DC counters, tire pressures, trips and what the energy actually
> costs on your electricity tariff.
>
> Everything is computed and stored on your iPhone. There is no account, no cloud, no
> analytics and no advertising.
>
> • Read-only by design — the app never sends control, coding or clear-fault commands.
> • All 192 cell voltages with weakest-cell ranking, module spread and a tap-to-detail view.
> • Battery health (SoH), remaining energy, temperatures, 12 V / LDC data and self-tests.
> • Charging power, AC/DC session counters and a charging self-test.
> • Trips with distance, energy, consumption and cost from an editable day/night tariff.
> • Tire pressures with size-aware cold-pressure guidance.
> • JSON/CSV export and a demo mode that works without a car.
>
> Requires a Bluetooth LE ELM327-compatible adapter (tested with vLinker iCar Pro BLE 4.0);
> classic-Bluetooth and Wi-Fi adapters are not supported. Battery and diagnostic values are
> informational estimates from manufacturer-specific data, not a substitute for a service
> inspection. Do not operate the app while driving.
>
> EV Info is not affiliated with or endorsed by Hyundai Motor Company. Hyundai and Ioniq
> are trademarks of Hyundai Motor Company.

**Support URL:** `https://psugarev.github.io/ev-info/support.html`
**Privacy policy URL:** `https://psugarev.github.io/ev-info/privacy.html`
**Marketing URL (optional):** `https://github.com/psugarev/ev-info`
**Copyright:** `2026 psugarev`
**Version:** `1.0` · **Build:** auto-incremented by `scripts/archive-appstore.sh`

## Category

Pick in ASC → App Information → **Category**: Primary **Utilities**, Secondary
**Navigation** (use **Travel** if Navigation is not offered for the category list).
The plist `LSApplicationCategoryType = public.app-category.utilities` is only the
platform declaration and does not choose the store category.

## Age rating

New age-rating questionnaire (2026): answer **No** to every content question
(violence, sexuality, profanity, alcohol/tobacco, gambling, medical/treatment
information, user-generated content, unrestricted web access, ads, in-app purchases).
Result: **4+**.

## Privacy label

- **Data Not Collected** — the app has no networking code, no analytics and no SDKs.
- Location and Bluetooth are used on-device only; the privacy policy explains it.

## Pricing

v1 is **free** with no in-app purchase (no paywall code exists). A one-time Pro
unlock (€9.99, launch €6.99) is the planned monetisation — tracked separately so the
free v1 can ship now.

## EU DSA trader status (**OWNER**)

ASC → Business → Compliance → **Trader status**: enter address, phone and contact,
verify the phone by SMS, confirm you are a trader (this is a paid app distribution
requirement in the EU; without it the app is removed from EU storefronts).

## Hardware demo video (**OWNER**)

Apple requires a **video (not a screen recording) of the app running on a physical
iPhone while it pairs with the adapter** for apps that need hardware. Suggested
30–60 s script:

1. Phone on the dashboard, adapter plugged into the OBD port.
2. Open EV Info → header shows `Initializing…` → stages → `OBD ready — ISO 15765-4`.
3. Tap Battery, show SoH and 12 V; tap Cells, show module blocks.
4. Plug in a charger for a few seconds (optional) to show charging power.
5. Say the file name here and put the public link into
   `Distribution/APP_REVIEW_NOTES.md` (`<link>` placeholder).

## Upload sequence (**OWNER**)

1. `scripts/archive-appstore.sh --export` → `build/EVInfo-1.0-<build>.ipa`
   (signed by your team; build number = git commit count unless overridden).
2. Upload with Xcode Organizer → Distribute App → App Store Connect, or
   Transporter.app. Each new upload needs a **higher build number** for version 1.0.
3. In ASC: create the app record with bundle id `com.evinfo.app`, paste the copy
   above, upload screenshots from `Distribution/screenshots/69/en` (and `bg` for the
   Bulgarian localisation), answer the age rating, set category, trader status.
4. Attach the demo video link in App Review notes and submit.
