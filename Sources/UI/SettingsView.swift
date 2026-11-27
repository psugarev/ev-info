import SwiftUI
import SwiftData

// MARK: - Settings
// Language, demo mode, OBD2 adapter, storage and app info. Tariff/cost editing
// lives in the Costs tab; charging lives in its own tab.

struct SettingsView: View {
    @EnvironmentObject var ble: BLETransport
    @EnvironmentObject var cloud: CloudService
    @Environment(\.modelContext) private var modelContext

    @AppStorage("appLanguage") private var appLanguage = "en"
    @AppStorage("demoModeEnabled") private var demoModeEnabled = false
    @AppStorage(DataRetention.settingKey) private var retentionDays = DataRetention.defaultDays

    @State private var confirmDeleteAll = false
    @State private var deleteError: String?

    @State private var cloudClientId = ""
    @State private var cloudClientSecret = ""
    @State private var cloudBusy = false

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    private var hasRealAdapterConnected: Bool {
        ble.connected && !ble.isDemo
    }

    var body: some View {
        Form {
            appSection
            demoSection
            adapterSection
            cloudSection
            storageSection
            aboutSection
        }
        .navigationTitle("Settings")
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .listRowBackground(Theme.surface)
        .tint(Theme.cyan)
        .confirmationDialog(
            "Delete all data?",
            isPresented: $confirmDeleteAll,
            titleVisibility: .visible
        ) {
            Button("Delete all data", role: .destructive, action: deleteAllData)
        } message: {
            Text("Trips, battery history, logs and raw OBD frames stored on this iPhone will be permanently deleted.")
        }
    }

    // MARK: - Sections

    private var appSection: some View {
        Section("App") {
            Picker("Language", selection: $appLanguage) {
                Text("English").tag("en")
                Text("Български").tag("bg")
            }
            .pickerStyle(.segmented)
            .onChange(of: appLanguage) { _, _ in
                ble.refreshLocalizedText()
            }
        }
    }

    private var demoSection: some View {
        Section {
            Toggle("Demo mode", isOn: $demoModeEnabled)
                .disabled(hasRealAdapterConnected)
        } footer: {
            Text("Shows a recorded sample session so you can explore every screen without an OBD2 adapter. Off by default. Demo data is never mixed with real vehicle data.")
        }
    }

    private var adapterSection: some View {
        Section("OBD2 adapter") {
            LabeledContent("Status", value: ble.statusMessage)
            LabeledContent("Bluetooth") {
                Text(bluetoothStateText)
            }

            if ble.isPermissionDenied {
                Button("Allow Bluetooth in Settings") {
                    SystemSettings.open()
                }
            }

            if ble.isDemo {
                Text("Turn off demo mode to connect a real adapter.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                adapterControls
            }

            NavigationLink("View Saved Raw OBD Log") {
                RawLogView(tripID: nil)
            }
        }
    }

    @ViewBuilder
    private var adapterControls: some View {
        if ble.connected {
            Button("Disconnect", role: .destructive) {
                ble.disconnect()
            }
            Button("Forget this adapter") {
                ble.disconnect()
                ble.forgetAdapter()
            }
        } else {
            Button("Scan for OBD2 adapter") {
                ble.scan()
            }
        }

        if !ble.discoveredAdapters.isEmpty && !ble.connected {
            ForEach(ble.discoveredAdapters) { adapter in
                Button {
                    ble.connect(to: adapter.id)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(adapter.name)
                            Text("Signal \(adapter.rssi) dBm")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Text("Connect")
                            .foregroundStyle(Theme.cyan)
                    }
                }
            }
        } else if !ble.connected {
            Text("Scan, then select your OBD2 adapter from nearby BLE devices.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - Cloud (Pleos)

    private var cloudSection: some View {
        Section {
            if cloud.isConfigured {
                LabeledContent("Status") {
                    Text(cloudStatusText)
                }
                if let updated = cloud.lastUpdatedText {
                    LabeledContent("Last update", value: updated)
                }
                if let vin = cloud.snapshot?.vin {
                    LabeledContent("VIN", value: vin)
                }
                Button {
                    Task { await cloud.refresh() }
                } label: {
                    Label("Refresh cloud data", systemImage: "arrow.clockwise")
                }
                .disabled(cloudBusy)

                Button("Disconnect", role: .destructive) {
                    cloud.disconnect()
                }
            } else {
                SecureField("Client ID", text: $cloudClientId)
                SecureField("Client Secret", text: $cloudClientSecret)
                Picker("Brand", selection: $cloud.brand) {
                    ForEach(PleosBrand.allCases) { brand in
                        Text(brand.title).tag(brand)
                    }
                }
                Button {
                    connectCloud()
                } label: {
                    HStack(spacing: 8) {
                        if cloudBusy { ProgressView() }
                        Text("Connect to Pleos")
                    }
                }
                .disabled(cloudBusy || cloudClientId.isEmpty || cloudClientSecret.isEmpty)
            }

            if let error = cloud.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Theme.red)
            }
        } header: {
            Text("Cloud data (Pleos)")
        } footer: {
            Text("Read-only official Pleos personal Vehicle Data API. The Client ID and Secret are kept in the iOS Keychain and sent only to api.pleos.ai. Nothing is written back to the car.")
        }
    }

    private var cloudStatusText: String {
        switch cloud.state {
        case .connected: return AppLocalization.string("Connected")
        case .connecting: return AppLocalization.string("Connecting…")
        case .notConfigured: return AppLocalization.string("Not connected")
        case .error: return AppLocalization.string("Error")
        }
    }

    private func connectCloud() {
        cloudBusy = true
        Task {
            do {
                try await cloud.connect(
                    clientId: cloudClientId,
                    clientSecret: cloudClientSecret,
                    brand: cloud.brand
                )
                cloudClientId = ""
                cloudClientSecret = ""
            } catch {
                // `cloud.lastError` carries the localised message.
            }
            cloudBusy = false
        }
    }

    private var storageSection: some View {
        Section {
            Picker("Keep detailed logs", selection: $retentionDays) {
                ForEach(DataRetention.options, id: \.self) { days in
                    if days == 0 {
                        Text("Forever").tag(days)
                    } else {
                        Text("\(days) days").tag(days)
                    }
                }
            }

            Button("Delete all data", role: .destructive) {
                confirmDeleteAll = true
            }

            if let deleteError {
                Text(deleteError)
                    .font(.caption)
                    .foregroundStyle(Theme.red)
            }
        } header: {
            Text("Storage")
        } footer: {
            Text("Older raw frames, telemetry rows and battery history are removed automatically. Trip summaries are kept until you delete them.")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("App", value: "EV Info")
            LabeledContent("Version", value: appVersion)
            LabeledContent("Tested with", value: "Hyundai Ioniq 5 RWD 2022")
            LabeledContent("Adapter", value: "vLinker iCar Pro BLE 4.0")

            DisclaimerFootnote()
            Text("EV Info only reads data and never writes to the car. It is not affiliated with or endorsed by Hyundai Motor Company. Hyundai and Ioniq are trademarks of Hyundai Motor Company.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - Helpers

    private var bluetoothStateText: LocalizedStringKey {
        switch ble.state {
        case .poweredOn: "On"
        case .poweredOff: "Off"
        case .unauthorized: "Not allowed"
        case .unknown: "Not started"
        default: "Unavailable"
        }
    }

    private func deleteAllData() {
        do {
            try DataRetention.deleteAll(in: modelContext)
            UserDefaults.standard.set(false, forKey: DemoData.seededHistoryKey)
            deleteError = nil
        } catch {
            AppLog.storage.error("Delete all failed: \(error.localizedDescription)")
            deleteError = String(localized: "Could not delete data. Please try again.")
        }
    }
}
