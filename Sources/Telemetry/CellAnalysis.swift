import Foundation

// MARK: - Cell Analysis
// UI-independent grouping and balance maths for the Cells screen. Pure value
// types so the grouping, highlighting and threshold rules can be unit tested
// without SwiftUI or a BLE connection.

/// One measured cell. `index` is 1-based across the pack, matching the cell
/// numbering the BMS reports (cells 1…192 in this app's decode).
struct CellReading: Identifiable, Equatable, Hashable {
    let index: Int
    let value: Double

    var id: Int { index }
}

/// How far a cell sits below the strongest cell in the pack. Thresholds match
/// the legend on the Cells screen: ≤ 10 mV is normal, a 10–30 mV gap is worth
/// watching, more than 30 mV suggests a weak cell.
enum CellBalance: Equatable {
    case good
    case watch
    case poor

    static let goodLimit = 0.010
    static let watchLimit = 0.030

    init(deltaToMax: Double) {
        if deltaToMax <= Self.goodLimit {
            self = .good
        } else if deltaToMax <= Self.watchLimit {
            self = .watch
        } else {
            self = .poor
        }
    }
}

/// A group of cells reported by one BMS cell block. The physical module
/// boundaries on the car are not exposed over OBD, so the app labels these
/// blocks as modules and says so in the UI.
struct CellModule: Identifiable, Equatable {
    /// 1-based block number.
    let index: Int
    /// First 1-based cell index in this block (1, 33, 65, …).
    let firstCellIndex: Int
    /// Number of cells this block can report (32 for the current decode).
    let expectedCells: Int
    /// Cells that have been read in this block, ascending by index.
    let readings: [CellReading]

    var id: Int { index }

    var lastCellIndex: Int { firstCellIndex + expectedCells - 1 }
    var readCount: Int { readings.count }
    var isComplete: Bool { readCount == expectedCells }

    var minVoltage: Double? { readings.map(\.value).min() }
    var maxVoltage: Double? { readings.map(\.value).max() }

    /// Spread inside this block, in volts.
    var spread: Double? {
        guard let minVoltage, let maxVoltage else { return nil }
        return max(0, maxVoltage - minVoltage)
    }

    var strongest: CellReading? {
        readings.max { $0.value < $1.value }
    }

    var weakest: CellReading? {
        readings.min { $0.value < $1.value }
    }

    /// Balance of the block as a whole, judged by its internal spread.
    var balance: CellBalance? {
        spread.map { CellBalance(deltaToMax: $0) }
    }

    func reading(at cellIndex: Int) -> CellReading? {
        readings.first { $0.index == cellIndex }
    }
}

/// Snapshot of all cell readings plus per-module grouping.
struct CellAnalysis {
    static let cellsPerModule = 32
    static let nominalCellCount = 192

    /// Every read cell, ascending by index.
    let readings: [CellReading]
    /// All blocks the BMS can report, including blocks not read yet.
    let modules: [CellModule]
    let totalCells: Int

    init(voltages: [Double?]) {
        let total = max(Self.nominalCellCount, voltages.count)
        var all: [CellReading] = []
        all.reserveCapacity(voltages.count)
        for (offset, value) in voltages.enumerated() {
            guard let value else { continue }
            all.append(CellReading(index: offset + 1, value: value))
        }
        readings = all
        totalCells = total

        var built: [CellModule] = []
        let moduleCount = (total + Self.cellsPerModule - 1) / Self.cellsPerModule
        for module in 0..<moduleCount {
            let first = module * Self.cellsPerModule + 1
            let last = min(first + Self.cellsPerModule - 1, total)
            let cells = all.filter { $0.index >= first && $0.index <= last }
            built.append(
                CellModule(
                    index: module + 1,
                    firstCellIndex: first,
                    expectedCells: last - first + 1,
                    readings: cells
                )
            )
        }
        modules = built
    }

    // MARK: Pack-wide values

    var readCount: Int { readings.count }

    var minVoltage: Double? { readings.map(\.value).min() }
    var maxVoltage: Double? { readings.map(\.value).max() }

    /// Pack spread in volts.
    var spread: Double {
        guard let minVoltage, let maxVoltage else { return 0 }
        return max(0, maxVoltage - minVoltage)
    }

    var strongest: CellReading? {
        readings.max { $0.value < $1.value }
    }

    /// Cells sorted from weakest upward, so the first entries are the ones
    /// worth looking at.
    var weakestRanking: [CellReading] {
        readings.sorted { $0.value < $1.value }
    }

    func moduleNumber(forCell index: Int) -> Int {
        ((max(index, 1) - 1) / Self.cellsPerModule) + 1
    }

    func module(forCell index: Int) -> CellModule? {
        let number = moduleNumber(forCell: index)
        return modules.first { $0.index == number }
    }

    /// How far this cell sits below the strongest cell, in volts (≥ 0).
    func deltaToMax(_ reading: CellReading) -> Double {
        guard let maxVoltage else { return 0 }
        return max(0, maxVoltage - reading.value)
    }

    func balance(for reading: CellReading) -> CellBalance {
        CellBalance(deltaToMax: deltaToMax(reading))
    }

    // MARK: Legend buckets

    /// How many read cells fall into each band, for the legend counters.
    var bucketCounts: (good: Int, watch: Int, poor: Int) {
        var good = 0
        var watch = 0
        var poor = 0
        for reading in readings {
            switch balance(for: reading) {
            case .good: good += 1
            case .watch: watch += 1
            case .poor: poor += 1
            }
        }
        return (good, watch, poor)
    }
}
