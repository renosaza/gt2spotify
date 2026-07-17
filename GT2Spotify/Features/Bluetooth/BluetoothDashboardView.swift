import CoreBluetooth
import SwiftUI
import UniformTypeIdentifiers

struct BluetoothDashboardView: View {
    @StateObject private var controller: BluetoothCentralController
    @State private var logEntries: [BluetoothLogEntry] = []
    @State private var exportDocument: BluetoothLogDocument?

    init(controller: BluetoothCentralController) {
        _controller = StateObject(wrappedValue: controller)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Bluetooth") {
                    LabeledContent("State", value: stateText(controller.state))
                    Text(controller.statusMessage).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Start Scan") { controller.startScan() }
                            .disabled(controller.state != .poweredOn || controller.isScanning)
                        Button("Stop Scan") { controller.stopScan() }
                            .disabled(!controller.isScanning)
                    }
                    Button("Refresh connected devices") { controller.refreshKnownDevices() }
                        .disabled(controller.state != .poweredOn)
                }

                Section("Remembered watch") {
                    if let remembered = controller.rememberedPeripheral {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(remembered.displayName).font(.headline)
                            Text(remembered.id.uuidString).font(.caption2).textSelection(.enabled)
                            LabeledContent("State", value: controller.connectionStateText(id: remembered.id))
                            if !remembered.advertisementSummary.isEmpty {
                                Text(remembered.advertisementSummary).font(.caption2).foregroundStyle(.secondary)
                            }
                            HStack {
                                Button("Connect") { controller.connect(id: remembered.id) }
                                Button("Forget", role: .destructive) { controller.forgetRememberedPeripheral() }
                            }
                        }
                    } else {
                        Text("After identifying the watch, tap Remember on that device. Its iOS Bluetooth identifier will be reused on future launches.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Already connected BLE candidates") {
                    Text("iOS cannot list every paired Bluetooth device. This section checks system-connected peripherals that expose FE01 or FE02.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if controller.connectedCandidates.isEmpty {
                        Text("No connected peripheral matched FE01 or FE02.")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(controller.connectedCandidates) { candidate in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(candidate.displayName).font(.headline)
                                if candidate.isRemembered {
                                    Image(systemName: "bookmark.fill").foregroundStyle(.secondary)
                                }
                            }
                            Text(candidate.id.uuidString).font(.caption2).textSelection(.enabled)
                            LabeledContent("Matched services", value: candidate.matchedServiceUUIDs.joined(separator: ", "))
                            LabeledContent("State", value: controller.connectionStateText(id: candidate.id))
                            HStack {
                                Button("Connect") { controller.connect(id: candidate.id) }
                                if !candidate.isRemembered {
                                    Button("Remember as watch") { controller.remember(id: candidate.id) }
                                }
                            }
                        }
                    }
                }

                Section("Discovered devices") {
                    if controller.discovered.isEmpty {
                        Text("No peripherals discovered. A watch already connected to Huawei Health may not advertise its name to this app.")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(controller.discovered) { peripheral in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(peripheral.displayName).font(.headline)
                                if peripheral.id == controller.rememberedPeripheralID {
                                    Image(systemName: "bookmark.fill").foregroundStyle(.secondary)
                                }
                            }
                            Text(peripheral.id.uuidString).font(.caption2).textSelection(.enabled)
                            LabeledContent("RSSI", value: "\(peripheral.rssi) dBm")
                            LabeledContent("Last seen", value: peripheral.lastSeen.formatted(date: .omitted, time: .standard))
                            if !peripheral.advertisementSummary.isEmpty {
                                Text(peripheral.advertisementSummary).font(.caption2).foregroundStyle(.secondary)
                            }
                            HStack {
                                Button("Connect") { controller.connect(id: peripheral.id) }
                                if peripheral.id != controller.rememberedPeripheralID {
                                    Button("Remember as watch") { controller.remember(id: peripheral.id) }
                                }
                            }
                        }
                    }
                }

                if let connected = controller.connectedPeripheral {
                    Section("Connected peripheral") {
                        Text(connected.displayName).font(.headline)
                        Text(connected.id.uuidString).font(.caption2).textSelection(.enabled)
                        LabeledContent("State", value: controller.connectionStateText(id: connected.id))
                        HStack {
                            if connected.id != controller.rememberedPeripheralID {
                                Button("Remember as watch") { controller.remember(id: connected.id) }
                            }
                            Button("Disconnect", role: .destructive) { controller.disconnect() }
                        }
                    }
                }

                Section("Services") {
                    if controller.services.isEmpty { Text("No services discovered").foregroundStyle(.secondary) }
                    ForEach(controller.services) { service in
                        DisclosureGroup {
                            ForEach(service.characteristics) { characteristic in
                                VStack(alignment: .leading) {
                                    Text(characteristic.uuid).monospaced()
                                    Text("properties: \(characteristic.properties.joined(separator: ", "))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(characteristic.isNotifying ? "notifying" : "not notifying")
                                        .font(.caption2)
                                }
                            }
                        } label: {
                            Text(service.uuid)
                                .monospaced()
                                .fontWeight(BluetoothUUIDFormatter.isHighlighted(service.uuid) ? .bold : .regular)
                        }
                    }
                }

                Section("Raw notifications") {
                    HStack {
                        Button("Refresh Log") { refreshLog() }
                        Button("Clear Log") {
                            Task {
                                await controller.clearLog()
                                logEntries = []
                            }
                        }
                        Button("Export Log") {
                            Task { exportDocument = BluetoothLogDocument(text: await controller.exportText()) }
                        }
                    }
                    ForEach(logEntries.suffix(200).reversed()) { entry in
                        VStack(alignment: .leading) {
                            Text("\(entry.timestamp.formatted(.dateTime.hour().minute().second().secondFraction(.fractional(3)))) \(entry.serviceUUID) / \(entry.characteristicUUID) \(entry.payload.count) bytes")
                                .font(.caption)
                                .fontWeight(BluetoothUUIDFormatter.isHighlighted(entry.serviceUUID) ? .bold : .regular)
                            Text(BluetoothHexFormatter.string(entry.payload))
                                .font(.caption2)
                                .monospaced()
                                .textSelection(.enabled)
                        }
                    }
                }

                Section("Safety boundary") {
                    Text("Discovery, connected-peripheral lookup, local identifier storage, connect/disconnect, service and characteristic inspection, notify/indicate subscription, and raw receive logging only. No writes, Huawei authentication, bonding, unpairing, reset, background reconnect, or BLE-driven Spotify control.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Bluetooth")
            .fileExporter(
                isPresented: Binding(get: { exportDocument != nil }, set: { if !$0 { exportDocument = nil } }),
                document: exportDocument,
                contentType: .plainText,
                defaultFilename: "gt2spotify-ble-log.txt"
            ) { _ in exportDocument = nil }
        }
    }

    private func refreshLog() {
        Task { logEntries = await controller.logSnapshot() }
    }

    private func stateText(_ state: CBManagerState) -> String {
        switch state {
        case .unknown: "Unknown"
        case .resetting: "Resetting"
        case .unsupported: "Unsupported"
        case .unauthorized: "Unauthorized"
        case .poweredOff: "Powered Off"
        case .poweredOn: "Powered On"
        @unknown default: "Unknown"
        }
    }
}

struct BluetoothLogDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    let text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        text = configuration.file.regularFileContents.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
