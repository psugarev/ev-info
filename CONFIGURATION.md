# Configuration

## Vehicle
```yaml
make: Hyundai
model: Ioniq 5
modelYear: 2022
drive: RWD
adapter: vLinker iCar Pro BLE 4.0
currency: EUR
```

## EVN example tariff from supplied invoice
Period: 09.09.2026–08.10.2026.

Energy-only prices:
- day: €0.09297/kWh
- night: €0.04103/kWh

The invoice also lists network charges of €0.02347 + €0.00419 + €0.00801 + €0.00018 = €0.03585/kWh before VAT. Therefore the application should calculate an all-in marginal tariff by adding the applicable network components and VAT, instead of assuming that the energy-only tariff is the final price.

The invoice total is €56.65 / 427 kWh = €0.13267/kWh blended. This is a useful sanity check, not a replacement for day/night allocation.

## Suggested initial all-in model
- day before VAT: 0.09297 + 0.03585 = €0.12882/kWh
- night before VAT: 0.04103 + 0.03585 = €0.07688/kWh
- with 20% VAT: day ≈ €0.15458/kWh; night ≈ €0.09226/kWh

Make every component editable in Settings.
