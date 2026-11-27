import SwiftUI
import SwiftData

// MARK: - IoniqDrive App Entry Point

@main
struct IoniqDriveApp: App {

    // MARK: - Persistent storage

    private static let persistence = PersistenceController.make()
    private static var container: ModelContainer { persistence.container }

    // MARK: - Shared state objects

    @AppStorage("appLanguage") private var appLanguage = "en"
    @AppStorage("demoModeEnabled") private var demoModeEnabled = false
    @AppStorage("disclaimerAccepted") private var disclaimerAccepted = false

    @StateObject private var ble = BLETransport()
    @StateObject private var telemetry = TelemetryEngine()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var recorder: TripRecorder
    @StateObject private var store: TelemetryStore

    @State private var obdSession: OBDSession?

    init() {
#if DEBUG
        // Design/screenshot harness: `-demo` turns demo mode on and skips the
        // first-run disclaimer so the screen can be captured directly.
        if ProcessInfo.processInfo.arguments.contains("-demo") {
            UserDefaults.standard.set(true, forKey: "demoModeEnabled")
            UserDefaults.standard.set(true, forKey: "disclaimerAccepted")
        }
#endif
        let context = Self.container.mainContext
        _recorder = StateObject(wrappedValue: TripRecorder(modelContext: context, tariffProfile: .load()))
        _store = StateObject(wrappedValue: TelemetryStore(modelContext: context))
    }

    var body: some Scene {
        WindowGroup {
            rootView
                .safeAreaInset(edge: .top, spacing: 0) { storageBanner }
                .environmentObject(ble)
                .environmentObject(telemetry)
                .environmentObject(locationManager)
                .environmentObject(recorder)
                .environmentObject(store)
                .environment(\.locale, Locale(identifier: appLanguage))
                .preferredColorScheme(.dark)
                .modelContainer(Self.container)
                .fullScreenCover(isPresented: disclaimerPresented) {
                    DisclaimerView { disclaimerAccepted = true }
                        .environment(\.locale, Locale(identifier: appLanguage))
                        .preferredColorScheme(.dark)
                }
                .task {
                    bindSessionIfNeeded()
                    syncDemoMode()
                    if Self.persistence.isPersistent {
                        DataRetention.purgeInBackground(container: Self.container)
                    }
                }
                .onChange(of: demoModeEnabled) { _, _ in
                    syncDemoMode()
                }
        }
    }

    private var disclaimerPresented: Binding<Bool> {
        Binding(get: { !disclaimerAccepted }, set: { _ in })
    }

    // MARK: - Root

    @ViewBuilder
    private var rootView: some View {
#if DEBUG
        if let route = DebugRoute.current {
            switch route {
            case .drive:
                DashboardView()
            case .battery:
                NavigationStack { BatteryDetailView() }
            case .cells:
                NavigationStack { CellVoltageView() }
            case .charging:
                NavigationStack { ChargingView() }
            case .history:
                NavigationStack { BatteryHistoryView() }
            case .costs:
                NavigationStack { CostsView() }
            case .trip:
                DemoTripDetailRoute()
            }
        } else {
            RootTabView()
        }
#else
        RootTabView()
#endif
    }

    /// Shown when the on-disk store could not be opened and the app is running
    /// on temporary storage, so the user is never silently left without saving.
    @ViewBuilder
    private var storageBanner: some View {
        if let reason = Self.persistence.failureReason {
            Label {
                Text("Storage unavailable — trips and history will not be saved.")
                    .font(.caption.weight(.semibold))
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .foregroundStyle(Theme.background)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(Theme.amber)
            .accessibilityHint(Text(reason))
        }
    }

    // MARK: - Session wiring

    @MainActor
    private func bindSessionIfNeeded() {
        guard obdSession == nil else { return }
        let session = OBDSession(transport: ble)
        session.initializationStatusDidChange = { [weak ble] status in
            ble?.showInitializationStatus(status)
        }
        telemetry.bind(session: session, location: locationManager)
        recorder.bind(session: session, locationManager: locationManager)
        store.bind(session: session)
        obdSession = session
    }

    // MARK: - Demo mode

    /// Applies the Settings → Demo mode toggle. Demo values are labelled in the
    /// UI and never reach the trip recorder or the vehicle pipeline.
    @MainActor
    private func syncDemoMode() {
        if demoModeEnabled {
            guard !ble.connected || ble.isDemo else {
                // A real adapter is connected; never overlay it with demo data.
                demoModeEnabled = false
                return
            }
            ble.setDemoConnection(true)
            telemetry.enableDemo(with: DemoData.liveSample())
            DemoData.seedHistory(container: Self.container)
            DemoData.seedTrips(container: Self.container)
        } else {
            ble.setDemoConnection(false)
            telemetry.disableDemo()
            DemoData.removeSeededHistory(container: Self.container)
            DemoData.removeSeededTrips(container: Self.container)
        }
    }
}

#if DEBUG
/// Opens the newest trip's detail for App Store screenshots.
private struct DemoTripDetailRoute: View {
    @Query(sort: \TripRecord.startDate, order: .reverse)
    private var trips: [TripRecord]

    var body: some View {
        NavigationStack {
            if let trip = trips.first {
                TripDetailView(trip: trip)
            } else {
                ContentUnavailableView(
                    "No trips yet",
                    systemImage: "car",
                    description: Text("Turn on Demo mode to seed sample trips.")
                )
            }
        }
    }
}

// MARK: - Debug route
// Design harness only: `-demoRoute drive|battery|cells|charging|history|costs|trip`
// opens one screen directly. Excluded from Release builds.

private enum DebugRoute: String {
    case drive
    case battery
    case cells
    case charging
    case history
    case costs
    case trip

    static var current: DebugRoute? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-demoRoute"),
              arguments.indices.contains(flag + 1) else { return nil }
        return DebugRoute(rawValue: arguments[flag + 1])
    }
}
#endif
