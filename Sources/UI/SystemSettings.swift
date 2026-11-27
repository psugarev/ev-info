import SwiftUI

// MARK: - System Settings shortcut
// Permission prompts can only be shown once. After a denial the only recovery
// is the app's page in the Settings app, so denied states link straight there.

enum SystemSettings {
    @MainActor
    static func open() {
#if os(iOS)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
#endif
    }
}
