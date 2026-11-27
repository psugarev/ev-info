import SwiftUI

// MARK: - Root Tabs
// Five sections: live drive screen, battery details/history, cell grid,
// charging and costs. Tires and trip history open from the Drive screen;
// Settings is in each screen's toolbar.

struct RootTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Drive", systemImage: "speedometer") }

            NavigationStack {
                BatteryDetailView()
            }
            .tabItem { Label("Battery", systemImage: "battery.100") }

            NavigationStack {
                CellVoltageView()
            }
            .tabItem { Label("Cells", systemImage: "square.grid.3x3") }

            NavigationStack {
                ChargingView()
            }
            .tabItem { Label("Charging", systemImage: "bolt.car") }

            NavigationStack {
                CostsView()
            }
            .tabItem { Label("Costs", systemImage: "eurosign.circle") }
        }
        .tint(Theme.cyan)
    }
}
