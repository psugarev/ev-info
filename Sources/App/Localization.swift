import Foundation

// MARK: - App localisation
// SwiftUI `Text("…")` keys follow the `.environment(\.locale)` set at the root
// from the language switch. Strings built outside SwiftUI — BLE status text,
// diagnostics, trip summaries, chart titles — used to stay English. They go
// through this helper so everything follows the same `appLanguage` setting.
//
// Interpolated values are substituted before the string leaves the helper, so
// catalog translations keep control of argument order (%@, %lld …).

enum AppLocalization {

    static let languageKey = "appLanguage"
    static let defaultLanguage = "en"

    /// Language selected in Settings → App → Language.
    static var languageCode: String {
        guard let stored = UserDefaults.standard.string(forKey: languageKey), !stored.isEmpty else {
            return defaultLanguage
        }
        return stored
    }

    static var locale: Locale {
        Locale(identifier: languageCode)
    }

    /// `String(localized:)` picks the bundle's preferred localisation, not the
    /// locale argument, so the selected language's `.lproj` must be opened
    /// explicitly. Falls back to the main bundle when the language has no
    /// resources (the source English text is shown in that case).
    static var localizedBundle: Bundle {
        guard let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }

    /// Translated string for the current app language.
    ///
    /// Falls back to the source English when the catalog has no entry, which is
    /// what the app showed before, so a missing translation never blanks a label.
    static func string(_ value: String.LocalizationValue) -> String {
        String(localized: value, table: "Localizable", bundle: localizedBundle, locale: locale)
    }

    /// Translated format string with already-formatted arguments. Keeps every
    /// catalog key a plain literal in the source, so the localisation check can
    /// verify that each one has a translation.
    static func format(_ key: String.LocalizationValue, _ arguments: String...) -> String {
        let translated = String(localized: key, table: "Localizable", bundle: localizedBundle, locale: locale)
        guard !arguments.isEmpty else { return translated }
        return String(format: translated, arguments: arguments)
    }

    /// Decimal number formatted for the app language (comma in Bulgarian).
    static func number(_ value: Double, decimals: Int) -> String {
        String(format: "%.\(decimals)f", locale: locale, arguments: [value])
    }
}
