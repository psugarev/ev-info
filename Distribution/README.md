# Sharing EV Info without paying for an Apple Developer account

This folder contains everything needed to put **EV Info** on a friend's iPhone
using **their own free Apple ID**. No paid Apple Developer Program membership is
required for this route.

> **The honest trade-off:** a free Apple ID produces *7-day* signatures, so the
> app stops opening after a week until it is re-signed (Sideloadly/AltStore/
> SideStore can refresh it automatically). There is **no legitimate way** to get
> a permanent, "normal" install without the $99/year Apple Developer Program
> (TestFlight, Ad Hoc, or App Store). Details at the end.

## Contents

| File | Purpose |
|---|---|
| `EVInfo-unsigned.ipa` | Unsigned Release build (arm64, iOS 17.6+, iPhone-only, ~1.4 MB) to give to friends |
| `make-unsigned-ipa.sh` | Rebuild the IPA after code changes |
| `build-with-your-apple-id.sh` | For friends with a Mac + Xcode: build and install straight from source |
| `IoniqDrive2-source.zip` | Full source (no build artifacts) for the Mac/Xcode route |

## Generate a fresh IPA

```sh
./Distribution/make-unsigned-ipa.sh
```

## Option 1 — Sideloadly (Windows or macOS) — simplest

Each friend does this on their own computer with their own Apple ID:

1. Install [Sideloadly](https://sideloadly.io/) (Windows/macOS) and iTunes
   (Windows only).
2. On the iPhone: **Settings → Privacy & Security → Developer Mode → On**
   (iOS 16+ requires it), then reboot and confirm.
3. Connect the iPhone by USB and tap **Trust**.
4. Open Sideloadly, drag in `EVInfo-unsigned.ipa`, type the friend's Apple ID
   (2FA is supported), and press **Start**.
5. On the iPhone: **Settings → General → VPN & Device Management** → tap the
   Apple ID → **Trust**.
6. Enable **automatic refresh** in Sideloadly and keep the computer on the same
   Wi-Fi (or plug in) so the daemon re-signs before the 7-day expiry.

## Option 2 — AltStore / SideStore (auto-refresh)

- **AltStore** ([altstore.io](https://altstore.io/)): install AltServer on a
  computer, install AltStore on the phone over Wi-Fi, then add the IPA in
  AltStore. AltServer refreshes the app in the background when the phone is on
  the same network.
- **SideStore** ([sidestore.io](https://sidestore.io/)): refreshes on-device
  (no computer needed after setup). On iOS 27 there are fully on-device
  installers (e.g. [AltLoad](https://github.com/mirazbakis/AltLoad)) that set it
  up without a computer.
- Both re-sign with the free Apple ID every 7 days automatically.

## Option 3 — friend has a Mac + Xcode

1. Install Xcode and sign in with the Apple ID: **Xcode → Settings → Accounts**.
2. Open the project (`IoniqDrive.xcodeproj`), select the **IoniqDrive** scheme,
   and under **Signing & Capabilities** choose the personal team.
3. Plug in the iPhone and press **Run**. Or use the script:

```sh
./Distribution/build-with-your-apple-id.sh
```

The script detects the team and connected iPhone automatically (or takes
`TEAM_ID` and `DEVICE_UDID` as arguments).

## Free-account limits (set by Apple, not by this app)

Source: [Apple Developer account help](https://developer.apple.com/help/account/basics/about-your-developer-account)

| Limit | Value |
|---|---|
| Provisioning profile lifetime | **7 days** |
| Apps installed per device | **3** |
| App IDs per 7 days | **10** |
| Devices registered per 7 days | **3** |

Practical consequences:

- Every friend signs with **their own** Apple ID — a signed build cannot be
  shared, only the unsigned IPA/source.
- Re-signing with the **same Apple ID and bundle ID** upgrades in place and
  keeps the app's local data.
- The app's icon and behaviour are normal; only the signature expires.

## Option 4 — pay Apple: the only "real app" route

The $99/year Apple Developer Program unlocks:

- **TestFlight** — invite friends by email or public link (up to 10,000 testers,
  builds valid 90 days). Closest thing to a normal install.
- **Ad Hoc** — 100 registered devices, signatures valid 1 year.
- **App Store** — permanent distribution.

There is no free equivalent, and EU alternative marketplaces still require a
paid developer account and Apple notarization. Avoid "enterprise certificate"
resale services — those certificates get revoked and the apps stop working.

## About this app specifically

- EV Info is a **read-only** Hyundai Ioniq 5 logger that talks to a
  vLinker/ELM327-compatible BLE adapter. Without that adapter and car, a friend
  sees empty screens — the Release build has no sample data.
- Requires **iOS 17.6+** on an iPhone (no iPad layout).
- No accounts, no networking, no third-party SDKs; all data stays on the device.
- If you want a "demo" build that seeds sample charts so friends can explore it
  without the car, that can be added as a separate debug/QA build.

## Official references

- Apple free-account limits: https://developer.apple.com/help/account/basics/about-your-developer-account
- Sideloadly FAQ (7-day, 3-app and 10-App-ID limits, iOS 27 support): https://sideloadly.io/faq.html
- AltStore: https://altstore.io/
- SideStore: https://sidestore.io/

## Накратко (BG)

1. Инсталирайте [Sideloadly](https://sideloadly.io/) на компютър (Windows/macOS).
2. На iPhone: **Settings → Privacy & Security → Developer Mode → On**, рестарт.
3. Свържете телефона с кабел и натиснете **Trust**.
4. Плъзнете `EVInfo-unsigned.ipa` в Sideloadly, въведете **свой Apple ID** и Start.
5. На iPhone: **Settings → General → VPN & Device Management** → доверете сертификата.
6. Приложението работи 7 дни; включете автоматично обновяване в Sideloadly или
   просто го инсталирайте отново със същия Apple ID (данните се запазват).

Безплатен Apple ID не позволява постоянно приложение или TestFlight — за това е
нужен платен Apple Developer Program (99 USD/година).

## App Store Connect kit

- [`AppStore/ASC_CHECKLIST.md`](AppStore/ASC_CHECKLIST.md) — listing copy, category,
  age-rating answers, privacy label, DSA trader steps, upload sequence and the
  owner-only checklist.
- `screenshots/{69,65}/{en,bg}/` — 6.9" and 6.5" screenshot sets.
- `PRIVACY_POLICY.md` and `APP_REVIEW_NOTES.md` — mirrored at
  https://psugarev.github.io/ev-info/privacy.html and
  https://psugarev.github.io/ev-info/support.html.
- `scripts/archive-appstore.sh` — signed archive/export with an automatic build
  number (`--dry-run` to preview, `--export` for the IPA).
