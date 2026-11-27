import os

// MARK: - App Log
// Central os.Logger categories. Replaces ad-hoc print() calls so diagnostics
// go to the unified log (and stay out of release console output).

enum AppLog {
    private static let subsystem = "com.evinfo.app"

    static let storage = Logger(subsystem: subsystem, category: "storage")
    static let bluetooth = Logger(subsystem: subsystem, category: "bluetooth")
    static let location = Logger(subsystem: subsystem, category: "location")
    static let cloud = Logger(subsystem: subsystem, category: "cloud")
}
