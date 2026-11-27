import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: - Theme
// Dark automotive telemetry palette. Deep near-black surfaces, cyan for live
// data, green for regen/positive battery state, amber for warnings, red for
// faults. Native SF fonts keep the app fast and Dynamic Type friendly.

enum Theme {
    static let background = Color(hex: 0x06080D)
    static let backgroundElevated = Color(hex: 0x0B1018)
    static let surface = Color(hex: 0x111722)
    static let surfaceElevated = Color(hex: 0x17202E)
    static let border = Color(hex: 0x223044)

    static let textPrimary = Color(hex: 0xF1F5F9)
    static let textSecondary = Color(hex: 0x94A3B8)
    // ≈6.7:1 on the card/background colours (WCAG AA needs 4.5:1; the former
    // #64748B measured 3.77:1).
    static let textTertiary = Color(hex: 0x8CA0B8)

    static let cyan = Color(hex: 0x22D3EE)
    static let green = Color(hex: 0x34D399)
    static let amber = Color(hex: 0xFBBF24)
    static let red = Color(hex: 0xF87171)
    static let violet = Color(hex: 0xA78BFA)

    static let speedGradient = AngularGradient(
        colors: [cyan, green, cyan.opacity(0.35)],
        center: .center,
        startAngle: .degrees(-90),
        endAngle: .degrees(270)
    )

    static let cardShape = RoundedRectangle(cornerRadius: 24, style: .continuous)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

extension Theme {
    /// Dark navigation/tab bars to match the app surfaces.
    static func configureAppearance() {
#if os(iOS)
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(backgroundElevated)
        tab.stackedLayoutAppearance.selected.iconColor = UIColor(cyan)
        tab.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor(cyan)]
        tab.stackedLayoutAppearance.normal.iconColor = UIColor(textTertiary)
        tab.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor(textTertiary)]
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(background)
        nav.titleTextAttributes = [.foregroundColor: UIColor(textPrimary)]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor(textPrimary)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
#endif
    }
}

// MARK: - Gauges

/// Tick-style state-of-charge gauge. The ring is drawn as 45 radial ticks so
/// the reading reads like an instrument cluster rather than a progress ring:
/// every fifth tick is longer, the filled ticks use the battery colour and a
/// small live dot marks the current value.
struct SOCGauge: View {
    let percent: Double
    let color: Color
    var isLive: Bool = true

    private let startAngle = 135.0
    private let totalAngle = 270.0
    private let tickCount = 45

    private var clampedPercent: Double {
        min(max(percent, 0), 100)
    }

    var body: some View {
        ZStack {
            Canvas { context, size in
                let side = min(size.width, size.height)
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = side / 2 - 2

                for index in 0..<tickCount {
                    let fraction = Double(index) / Double(tickCount - 1)
                    let angle = Angle.degrees(startAngle + totalAngle * fraction)
                    let isMajor = index % 5 == 0
                    let length: CGFloat = isMajor ? 9 : 5
                    let active = isLive && fraction <= clampedPercent / 100 + 0.0001

                    var path = Path()
                    path.move(to: point(center: center, radius: radius - length, angle: angle))
                    path.addLine(to: point(center: center, radius: radius, angle: angle))
                    context.stroke(
                        path,
                        with: .color(active ? color : Theme.border.opacity(isMajor ? 0.9 : 0.5)),
                        style: StrokeStyle(lineWidth: isMajor ? 2.2 : 1.3, lineCap: .round)
                    )
                }

                guard isLive, clampedPercent > 0 else { return }
                let angle = Angle.degrees(startAngle + totalAngle * clampedPercent / 100)
                let dot = point(center: center, radius: radius - 1, angle: angle)
                context.fill(
                    Path(ellipseIn: CGRect(x: dot.x - 5, y: dot.y - 5, width: 10, height: 10)),
                    with: .color(color.opacity(0.22))
                )
                context.fill(
                    Path(ellipseIn: CGRect(x: dot.x - 2.4, y: dot.y - 2.4, width: 4.8, height: 4.8)),
                    with: .color(color)
                )
            }

            VStack(spacing: -2) {
                Text(String(format: "%.0f", clampedPercent))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .minimumScaleFactor(0.7)
                Text("%")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("State of charge"))
        .accessibilityValue("\(Int(clampedPercent.rounded())) percent")
    }

    private func point(center: CGPoint, radius: CGFloat, angle: Angle) -> CGPoint {
        CGPoint(
            x: center.x + radius * cos(angle.radians),
            y: center.y + radius * sin(angle.radians)
        )
    }
}

// MARK: - Card

struct TelemetryCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: Theme.cardShape)
            .overlay(
                Theme.cardShape.stroke(Theme.border, lineWidth: 1)
            )
    }
}

// MARK: - Labels

struct CardLabel: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .tracking(1.4)
            .foregroundStyle(Theme.textTertiary)
    }
}

struct MetricValue: View {
    let value: String
    let unit: String
    var color: Color = Theme.textPrimary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
            Text(unit)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}


// MARK: - Info

struct InfoCard: View {
    let icon: String
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.cyan)
                .frame(width: 26, height: 26)
                .background(Theme.cyan.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text(text)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceElevated.opacity(0.65), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
    }
}


// MARK: - Shared toolbar

private struct SettingsToolbarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
        }
    }
}

extension View {
    func settingsToolbar() -> some View {
        modifier(SettingsToolbarModifier())
    }
}
