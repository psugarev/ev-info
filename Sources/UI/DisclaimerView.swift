import SwiftUI

// MARK: - First-run disclaimer
// The app prints PASS / WARN / FAIL battery verdicts, which is safety-adjacent.
// Shown once before first use; the same wording lives in Settings → About.

struct DisclaimerView: View {
    let onAccept: () -> Void

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.cyan)
                        .accessibilityHidden(true)

                    Text("Before you start")
                        .font(.largeTitle.bold())
                        .foregroundStyle(Theme.textPrimary)

                    point("gauge.with.dots.needle.33percent",
                          "Informational only",
                          "Battery, cell and diagnostic results are estimates built from manufacturer-specific data that has not been validated against your car. They are not a substitute for a service inspection.")
                    point("car.fill",
                          "Not while driving",
                          "Do not operate or read the app while driving. Let a passenger use it, or stop in a safe place.")
                    point("lock.shield.fill",
                          "Read-only",
                          "EV Info only reads data. It never sends control, coding or clear-fault commands to the vehicle.")
                    point("iphone",
                          "Stays on your iPhone",
                          "No account, no server and no analytics. Everything is stored on this device.")

                    Text("EV Info is not affiliated with or endorsed by Hyundai Motor Company. Hyundai and Ioniq are trademarks of Hyundai Motor Company.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)

                    Button(action: onAccept) {
                        Text("I understand")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundStyle(Theme.background)
                            .background(Theme.cyan, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }
                .padding(24)
            }
        }
        .interactiveDismissDisabled()
    }

    private func point(_ icon: String, _ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(Theme.cyan)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Inline footnote
// One-line reminder under diagnostic verdicts (Battery, Charging).

struct DisclaimerFootnote: View {
    var body: some View {
        Label {
            Text("Informational only — not a substitute for a service inspection. Do not use while driving.")
        } icon: {
            Image(systemName: "info.circle")
        }
        .font(.caption)
        .foregroundStyle(Theme.textSecondary)
    }
}
