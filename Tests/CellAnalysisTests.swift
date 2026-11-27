import XCTest
#if canImport(IoniqDriveCore)
@testable import IoniqDriveCore
#else
@testable import IoniqDrive
#endif

final class CellAnalysisTests: XCTestCase {

    // MARK: - Helpers

    /// 192 cells around 3.66 V with a small wave, mirroring the demo pack.
    private func balancedPack(delta: Double = 0.004) -> [Double?] {
        (0..<192).map { index in
            3.664 + sin(Double(index) * 0.55) * delta
        }
    }

    /// Same pack as the demo data: three deliberate outliers at cells 42, 98
    /// and 151 (1-based), which must remain the three weakest cells.
    private func demoPack() -> [Double?] {
        var voltages = balancedPack()
        voltages[41] = 3.628
        voltages[97] = 3.641
        voltages[150] = 3.648
        return voltages
    }

    // MARK: - Grouping

    func testFullPackSplitsIntoSixModulesOf32() {
        let analysis = CellAnalysis(voltages: demoPack())

        XCTAssertEqual(analysis.totalCells, 192)
        XCTAssertEqual(analysis.readCount, 192)
        XCTAssertEqual(analysis.modules.count, 6)

        for (offset, module) in analysis.modules.enumerated() {
            XCTAssertEqual(module.index, offset + 1)
            XCTAssertEqual(module.firstCellIndex, offset * 32 + 1)
            XCTAssertEqual(module.expectedCells, 32)
            XCTAssertEqual(module.readCount, 32)
            XCTAssertTrue(module.isComplete)
        }

        XCTAssertEqual(analysis.modules[0].readings.first?.index, 1)
        XCTAssertEqual(analysis.modules[0].readings.last?.index, 32)
        XCTAssertEqual(analysis.modules[5].readings.first?.index, 161)
        XCTAssertEqual(analysis.modules[5].readings.last?.index, 192)
    }

    func testModuleNumberBoundaries() {
        let analysis = CellAnalysis(voltages: balancedPack())

        XCTAssertEqual(analysis.moduleNumber(forCell: 1), 1)
        XCTAssertEqual(analysis.moduleNumber(forCell: 32), 1)
        XCTAssertEqual(analysis.moduleNumber(forCell: 33), 2)
        XCTAssertEqual(analysis.moduleNumber(forCell: 97), 4)
        XCTAssertEqual(analysis.moduleNumber(forCell: 192), 6)
    }

    func testPartiallyReadPackKeepsAllModuleSlots() {
        // Only the first 40 cells have been polled so far.
        let voltages = Array(balancedPack().prefix(40)) + [Double?](repeating: nil, count: 152)
        let analysis = CellAnalysis(voltages: voltages)

        XCTAssertEqual(analysis.readCount, 40)
        XCTAssertEqual(analysis.modules.count, 6)
        XCTAssertEqual(analysis.modules[0].readCount, 32)
        XCTAssertEqual(analysis.modules[1].readCount, 8)
        XCTAssertEqual(analysis.modules[1].isComplete, false)
        XCTAssertEqual(analysis.modules[2].readCount, 0)
        XCTAssertNil(analysis.modules[2].minVoltage)
        XCTAssertNil(analysis.modules[2].balance)
    }

    func testGapInsideModuleCountsAsIncomplete() {
        var voltages = balancedPack()
        voltages[9] = nil // cell 10
        let analysis = CellAnalysis(voltages: voltages)

        XCTAssertEqual(analysis.readCount, 191)
        XCTAssertEqual(analysis.modules[0].readCount, 31)
        XCTAssertFalse(analysis.modules[0].isComplete)
        XCTAssertNil(analysis.modules[0].reading(at: 10))
    }

    // MARK: - Weakest cells (demo outliers)

    func testDemoOutliersAreTheThreeWeakestCells() {
        let analysis = CellAnalysis(voltages: demoPack())
        let weakest = analysis.weakestRanking.prefix(3)

        XCTAssertEqual(weakest.map(\.index), [42, 98, 151])
        XCTAssertEqual(weakest.map { analysis.moduleNumber(forCell: $0.index) }, [2, 4, 5])
    }

    func testDeltaToMaxUsesStrongestCell() {
        let analysis = CellAnalysis(voltages: demoPack())
        let weakest = analysis.weakestRanking[0]

        XCTAssertEqual(weakest.index, 42)
        XCTAssertEqual(analysis.deltaToMax(weakest), 0.040, accuracy: 0.0005)
        XCTAssertEqual(analysis.balance(for: weakest), .poor)
    }

    func testPerModuleSpreadAndExtremes() {
        let analysis = CellAnalysis(voltages: demoPack())

        // Module 2 holds the weakest cell (42) and none of the others.
        let module2 = analysis.modules[1]
        XCTAssertEqual(module2.weakest?.index, 42)
        XCTAssertEqual(module2.weakest?.value ?? 0, 3.628, accuracy: 0.0005)
        XCTAssertNotNil(module2.strongest)
        XCTAssertGreaterThan(module2.spread ?? 0, 0.030)

        // Module 1 is balanced, apart from natural ripple.
        let module1 = analysis.modules[0]
        XCTAssertEqual(module1.balance, .good)
        XCTAssertLessThan(module1.spread ?? 1, 0.010)
    }

    // MARK: - Thresholds and legend buckets

    func testBalanceThresholds() {
        XCTAssertEqual(CellBalance(deltaToMax: 0.000), .good)
        XCTAssertEqual(CellBalance(deltaToMax: 0.010), .good)
        XCTAssertEqual(CellBalance(deltaToMax: 0.0101), .watch)
        XCTAssertEqual(CellBalance(deltaToMax: 0.030), .watch)
        XCTAssertEqual(CellBalance(deltaToMax: 0.0301), .poor)
    }

    func testBucketCountsMatchReadings() {
        let analysis = CellAnalysis(voltages: demoPack())
        let buckets = analysis.bucketCounts

        XCTAssertEqual(buckets.good + buckets.watch + buckets.poor, analysis.readCount)
        XCTAssertEqual(buckets.poor, 1) // cell 42 is 40 mV below the max
        XCTAssertEqual(buckets.watch, 2) // cells 98 and 151
    }

    func testEmptyPackHasNoReadings() {
        let analysis = CellAnalysis(voltages: [])

        XCTAssertEqual(analysis.readCount, 0)
        XCTAssertEqual(analysis.modules.count, 6)
        XCTAssertNil(analysis.strongest)
        XCTAssertNil(analysis.minVoltage)
        XCTAssertEqual(analysis.spread, 0)
        XCTAssertEqual(analysis.bucketCounts.good, 0)
    }
}
