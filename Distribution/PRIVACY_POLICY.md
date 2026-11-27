# EV Info — Privacy Policy

> **Hosted at:** https://psugarev.github.io/ev-info/privacy.html — enter that URL in
> App Store Connect → App Information → Privacy Policy URL. The hosted page is
> `docs/privacy.html` in this repository (GitHub Pages, branch `main`, folder `/docs`).

**Last updated:** 27 November 2026

EV Info reads vehicle data from an ELM327-compatible Bluetooth OBD2 adapter and
stores it locally on your iPhone.

## What the app collects

**None.** There is no account, no server, no analytics, no advertising and no
third-party SDK. Trip data, battery history, diagnostic reports, GPS track
points and settings stay in the app's local storage on your device. The app
makes no network requests of its own.

## Location

Used only while you record a trip, to measure distance, speed and route when the
car does not report them over OBD2. Reverse geocoding of a trip's start and end
point is performed by Apple's CoreLocation service. Location is not used in the
background.

## Bluetooth

Used only to connect to your OBD2 adapter. The app only reads data from the
vehicle; it never sends control, coding or clear-fault commands.

## Export

JSON and CSV files are created on your device only when you tap Prepare, and go
wherever you choose to send them through the iOS share sheet.

## Your control over your data

- Delete a single trip (and its raw OBD frames) from Trip History.
- Choose how long detailed logs are kept in Settings → Storage.
- Erase everything with Settings → Storage → Delete all data.
- Deleting the app removes all stored data.

## Contact

Questions or data requests: open an issue at
https://github.com/psugarev/ev-info/issues/new/choose

## Not affiliated

EV Info is not affiliated with or endorsed by Hyundai Motor Company. Hyundai and
Ioniq are trademarks of Hyundai Motor Company.
