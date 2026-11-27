import Foundation

// MARK: - Pleos payload parser
// The Vehicle Data API returns nested objects with `{ value, unit, timestamp }`
// leaves and arrays keyed by `type`. This parser is deliberately tolerant: an
// unknown field is ignored, a known field with an unexpected unit is ignored
// instead of guessing, and nothing here ever invents a value.

enum PleosSnapshotParser {

    static func parse(
        vin: String,
        fetchedAt: Date,
        payloads: [String: Any]
    ) -> CloudVehicleData {
        var data = CloudVehicleData(vin: vin, fetchedAt: fetchedAt)
        let batteries = payloads["batteries"]
        let powertrains = payloads["powertrains"]
        let driving = payloads["driving"]
        let status = payloads["status"]
        let locations = payloads["locations"]

        // Battery / charging — documented paths first, then a tolerant fallback
        // that finds the field anywhere in the payload (the API may wrap the
        // endpoint object one level deeper than the docs suggest).
        data.socPercent = percent(batteries, ["charge", "stateOfCharge"])
            ?? percentDeep(batteries, ["stateOfCharge", "soc"])
        data.isCharging = bool(batteries, ["charge", "charging"]) ?? boolDeep(batteries, ["charging"])
        data.isPluggedIn = bool(batteries, ["charge", "plugIn"]) ?? boolDeep(batteries, ["plugIn"])
        data.chargeRemainingMinutes = minutes(batteries, ["charge", "remainTime"])
            ?? minutesDeep(batteries, ["remainTime", "remainingTime"])
        data.chargeStatusText = string(batteries, ["charge", "status"]) ?? stringDeep(batteries, ["status"])
        data.batteryCapacityKWh = energyKWh(batteries, ["charge", "batteryCapacity"])
        data.targetSOCStandard = percent(batteries, ["charge", "targetStateOfCharge", "standard"])
        data.targetSOCQuick = percent(batteries, ["charge", "targetStateOfCharge", "quick"])

        // Powertrain
        data.powertrainSOCPercent = percent(powertrains, ["batteries", "main", "remainRatio"])
            ?? percentDeep(powertrains, ["remainRatio"])
        data.rangeKm = distanceKm(powertrains, ["distanceToEmpties"], type: "ev")
            ?? distanceDeep(powertrains, "distanceToEmpties", type: "ev")

        // Driving
        data.odometerKm = distanceKm(driving, ["odometer"]) ?? distanceDeep(driving, "odometer", type: nil)
        if let park = string(driving, ["transmission", "parkingPosition"]) {
            data.isInPark = park.lowercased() == "p" || park.lowercased() == "park"
        }

        // Location (a list of points; the last one wins)
        data.latitude = number(locations, ["location", "latitude"]) ?? numberDeep(locations, ["latitude"])
        data.longitude = number(locations, ["location", "longitude"]) ?? numberDeep(locations, ["longitude"])

        // Status
        data.outsideTemperatureC = celsius(status, ["outsideTemperature"]) ?? celsiusDeep(status, ["outsideTemperature"])
        data.climateOn = bool(status, ["climateControl", "status"]) ?? boolDeep(status, ["climateControl", "status"])
        data.warnings = warningList(status)
        data.isLocked = doorLockState(status)

        return data
    }

    // MARK: - Leaf lookup

    private struct Leaf {
        let value: Any
        let unit: String?
    }

    private static func leaf(_ payload: Any?, path: [String], type: String? = nil) -> Leaf? {
        var current: Any? = payload
        for key in path {
            guard let dict = current as? [String: Any] else { return nil }
            current = dict[key]
        }
        if let list = current as? [Any] {
            if let type {
                current = list.last { ($0 as? [String: Any])?["type"] as? String == type }
            } else {
                current = list.last
            }
        }
        guard var dict = current as? [String: Any], let first = dict["value"] else { return nil }
        var value = first
        var unit = dict["unit"] as? String
        // Some endpoints nest another { value, unit } wrapper inside an array
        // element; unwrap up to three levels and keep the innermost unit.
        var depth = 0
        while let nested = value as? [String: Any], let inner = nested["value"], depth < 3 {
            unit = nested["unit"] as? String ?? unit
            value = inner
            depth += 1
        }
        return Leaf(value: value, unit: unit)
    }

    // MARK: - Typed readers

    private static func number(_ payload: Any?, _ path: [String], type: String? = nil) -> Double? {
        guard let leaf = leaf(payload, path: path, type: type) else { return nil }
        if let number = leaf.value as? Double { return number.isFinite ? number : nil }
        if let number = leaf.value as? Int { return Double(number) }
        if let number = leaf.value as? NSNumber { return number.doubleValue }
        if let text = leaf.value as? String, let number = Double(text) {
            return number.isFinite ? number : nil
        }
        return nil
    }

    private static func percent(_ payload: Any?, _ path: [String]) -> Double? {
        guard let value = number(payload, path), (0...100).contains(value) else { return nil }
        return value
    }

    private static func string(_ payload: Any?, _ path: [String], type: String? = nil) -> String? {
        guard let leaf = leaf(payload, path: path, type: type) else { return nil }
        return leaf.value as? String
    }

    private static func bool(_ payload: Any?, _ path: [String]) -> Bool? {
        guard let leaf = leaf(payload, path: path) else { return nil }
        if let value = leaf.value as? Bool { return value }
        guard let text = leaf.value as? String else { return nil }
        switch text.lowercased() {
        case "on", "true", "charging", "running", "locked", "1":
            return true
        case "off", "false", "notcharging", "stopped", "unlocked", "0":
            return false
        default:
            return nil
        }
    }

    /// Distance converted to kilometres; unknown units are dropped.
    private static func distanceKm(_ payload: Any?, _ path: [String], type: String? = nil) -> Double? {
        guard let leaf = leaf(payload, path: path, type: type),
              let amount = numericValue(leaf.value) else { return nil }
        switch leaf.unit?.lowercased() ?? "km" {
        case "km", "kilometer", "kilometers":
            return amount
        case "m", "meter", "meters":
            return amount / 1_000
        case "mile", "miles", "mi":
            return amount * 1.609_344
        case "feet", "ft":
            return amount * 0.000_304_8
        default:
            return nil
        }
    }

    private static func celsius(_ payload: Any?, _ path: [String]) -> Double? {
        guard let leaf = leaf(payload, path: path), let amount = numericValue(leaf.value) else { return nil }
        switch leaf.unit?.uppercased() ?? "C" {
        case "C":
            return amount
        case "F":
            return (amount - 32) / 1.8
        default:
            return nil
        }
    }

    private static func minutes(_ payload: Any?, _ path: [String]) -> Int? {
        guard let value = number(payload, path), value >= 0, value <= 65_535 else { return nil }
        return Int(value.rounded())
    }

    private static func energyKWh(_ payload: Any?, _ path: [String]) -> Double? {
        guard let leaf = leaf(payload, path: path), let amount = numericValue(leaf.value) else { return nil }
        switch leaf.unit?.lowercased() ?? "kwh" {
        case "kwh":
            return amount
        case "kj":
            return amount / 3_600
        default:
            return nil
        }
    }

    private static func numericValue(_ value: Any) -> Double? {
        if let number = value as? Double { return number.isFinite ? number : nil }
        if let number = value as? Int { return Double(number) }
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String, let number = Double(text) { return number.isFinite ? number : nil }
        return nil
    }

    // MARK: - Tolerant fallbacks

    /// First leaf whose key matches one of `keys` anywhere under `payload`.
    private static func deepLeaf(_ payload: Any?, keys: [String], type: String? = nil) -> Leaf? {
        guard let payload else { return nil }
        var queue: [Any] = [payload]
        let wanted = Set(keys.map { $0.lowercased() })
        while !queue.isEmpty {
            let current = queue.removeFirst()
            if let dict = current as? [String: Any] {
                if let found = keys.first(where: { dict[$0] != nil }) {
                    if let leaf = leaf(dict[found], path: []), leaf.value is [String: Any] == false {
                        return leaf
                    }
                }
                // A leaf wrapper itself.
                if let value = dict["value"], !(value is [String: Any]), !(value is [Any]) {
                    return Leaf(value: value, unit: dict["unit"] as? String)
                }
                for (key, child) in dict {
                    if wanted.contains(key.lowercased()), let childDict = child as? [String: Any] {
                        if let leaf = leaf(childDict, path: []) { return leaf }
                        if let value = childDict["value"] {
                            return Leaf(value: value, unit: childDict["unit"] as? String)
                        }
                    }
                }
                queue.append(contentsOf: dict.values)
            } else if let list = current as? [Any] {
                if let type {
                    for item in list.reversed() where (item as? [String: Any])?["type"] as? String == type {
                        queue.insert(item, at: 0)
                        break
                    }
                }
                queue.append(contentsOf: list)
            }
        }
        return nil
    }

    private static func numberDeep(_ payload: Any?, _ keys: [String]) -> Double? {
        guard let leaf = deepLeaf(payload, keys: keys), let value = numericValue(leaf.value) else { return nil }
        return value
    }

    private static func percentDeep(_ payload: Any?, _ keys: [String]) -> Double? {
        guard let value = numberDeep(payload, keys), (0...100).contains(value) else { return nil }
        return value
    }

    private static func boolDeep(_ payload: Any?, _ keys: [String]) -> Bool? {
        guard let leaf = deepLeaf(payload, keys: keys), let text = leaf.value as? String else { return nil }
        switch text.lowercased() {
        case "on", "true", "charging", "running", "locked", "1": return true
        case "off", "false", "notcharging", "stopped", "unlocked", "0": return false
        default: return nil
        }
    }

    private static func stringDeep(_ payload: Any?, _ keys: [String]) -> String? {
        deepLeaf(payload, keys: keys)?.value as? String
    }

    private static func minutesDeep(_ payload: Any?, _ keys: [String]) -> Int? {
        guard let value = numberDeep(payload, keys), value >= 0, value <= 65_535 else { return nil }
        return Int(value.rounded())
    }

    private static func distanceDeep(_ payload: Any?, _ key: String, type: String?) -> Double? {
        guard let leaf = deepLeaf(payload, keys: [key], type: type), let amount = numericValue(leaf.value) else { return nil }
        switch leaf.unit?.lowercased() ?? "km" {
        case "km", "kilometer", "kilometers": return amount
        case "m", "meter", "meters": return amount / 1_000
        case "mile", "miles", "mi": return amount * 1.609_344
        case "feet", "ft": return amount * 0.000_304_8
        default: return nil
        }
    }

    private static func celsiusDeep(_ payload: Any?, _ keys: [String]) -> Double? {
        guard let leaf = deepLeaf(payload, keys: keys), let amount = numericValue(leaf.value) else { return nil }
        switch leaf.unit?.uppercased() ?? "C" {
        case "C": return amount
        case "F": return (amount - 32) / 1.8
        default: return nil
        }
    }

    // MARK: - Compound fields

    private static func warningList(_ status: Any?) -> [String] {
        guard let dict = status as? [String: Any], let warnings = dict["warnings"] as? [Any] else { return [] }
        return warnings.compactMap { $0 as? String }.filter { !$0.isEmpty && $0 != "invalid" }
    }

    /// Doors report "open" / "closed" / "locked". Locked only when every door is
    /// explicitly locked; anything else stays unknown rather than guessing.
    private static func doorLockState(_ status: Any?) -> Bool? {
        guard let dict = status as? [String: Any],
              let doors = dict["doors"] as? [Any], !doors.isEmpty else { return nil }
        let values = doors.compactMap { ($0 as? [String: Any])?["value"] as? String }.map { $0.lowercased() }
        guard values.count == doors.count else { return nil }
        if values.contains("open") { return false }
        return values.allSatisfy { $0 == "locked" }
    }
}
