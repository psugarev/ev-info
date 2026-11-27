import XCTest

/// Guards the two things the App Store review and the Bulgarian UI depend on:
/// no key ships without a Bulgarian value, and nothing stays marked stale.
/// The source-usage check (every `Text("…")`/`AppLocalization` key exists) lives
/// in `scripts/check-localization.py` and runs in CI.
final class LocalizationCatalogTests: XCTestCase {

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // repo root
    }

    private func strings(in file: String) throws -> [String: [String: Any]] {
        let url = repoRoot.appendingPathComponent(file)
        let data = try Data(contentsOf: url)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(root["strings"] as? [String: [String: Any]])
    }

    private func value(_ entry: [String: Any], _ language: String) -> String? {
        let localizations = entry["localizations"] as? [String: Any]
        let languageEntry = localizations?[language] as? [String: Any]
        let unit = languageEntry?["stringUnit"] as? [String: Any]
        return unit?["value"] as? String
    }

    func testEveryStringHasEnglishAndBulgarian() throws {
        let catalog = try strings(in: "Resources/Localizable.xcstrings")
        XCTAssertGreaterThan(catalog.count, 200)

        for (key, entry) in catalog.sorted(by: { $0.key < $1.key }) {
            // The empty key is a placeholder Xcode writes; it carries no copy.
            if key.isEmpty { continue }
            let english = value(entry, "en")
            let bulgarian = value(entry, "bg")
            XCTAssertFalse(english?.isEmpty ?? true, "Missing English for \(key)")
            XCTAssertFalse(bulgarian?.isEmpty ?? true, "Missing Bulgarian for \(key)")
        }
    }

    func testNoStaleStrings() throws {
        let catalog = try strings(in: "Resources/Localizable.xcstrings")
        let stale = catalog.filter { ($0.value["extractionState"] as? String) == "stale" }
        XCTAssertTrue(stale.isEmpty, "Stale catalog keys: \(stale.keys.sorted())")
    }

    func testInfoPlistStringsAreLocalised() throws {
        let strings = try strings(in: "Resources/InfoPlist.xcstrings")
        XCTAssertFalse(strings.isEmpty)
        for (key, entry) in strings {
            XCTAssertFalse(value(entry, "en")?.isEmpty ?? true, "Missing English for \(key)")
            XCTAssertFalse(value(entry, "bg")?.isEmpty ?? true, "Missing Bulgarian for \(key)")
        }
    }
}
