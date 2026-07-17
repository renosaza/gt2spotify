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
                }

                Section("Discovered devices") {
                    if controller.discovered.isEmpty {
                        Text("No peripherals discovered. A watch already connected to Huawei Health may not advertise to this app.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(controller.discovered) { peripheral in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(peripheral.displayName).font(.headline)
                            Text(peripheral.id.uuidString).font(.caption2).textSelection(.enabled)
                            LabeledContent("RSSI", value: "\(peripheral.rssi) dBm")
                            LabeledContent("Last seen", value: peripheral.lastSeen.formatted(date: .omitted, time: .standard))
                            if !peripheral.advertisementSummary.isEmpty {
                                Text(peripheral.advertisementSummary).font(.caption2).foregroundStyle(.secondary)
                            }
                            Button("Connect") { controller.connect(id: peripheral.id) }
                        }
                    }
                }

                if let connected = controller.connectedPeripheral {
                    Section("Connected peripheral") {
                        Text(connected.displayName).font(.headline)
                        Text(connected.id.uuidString).font(.caption2).textSelection(.enabled)
                        Button("Disconnect", role: .destructive) { controller.disconnect() }
                    }
                }

                Section("Services") {
                    if controller.services.isEmpty { Text("No services discovered").foregroundStyle(.secondary) }
                    ForEach(controller.services) { service in
                        DisclosureGroup {
                            ForEach(service.characteristics) { characteristic in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(characteristic.uuid).font(.subheadline).monospaced()
                                    Text("properties: \(characteristic.properties.joined(separator: ", "))")
                                        .font(.caption).foregroundStyle(.secondary)
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
                        Button("Clear Log", role: .destructive) {
                            Task { await controller.clearLog(); await MainActor.run { logEntries = [] } }
                        }
                        Button("Export Log") {
                            Task {
                                let text = await controller.exportText()
                                await MainActor.run { exportDocument = BluetoothLogDocument(text: text) }
                            }
                        }
                    }
                    ForEach(logEntries.suffix(200).reversed()) { entry in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(entry.timestamp.formatted(.dateTime.hour().minute().second().secondFraction(.fractional(3))))  \(entry.serviceUUID) / \(entry.characteristicUUID)  \(entry.payload.count) bytes")
                                .font(.caption).fontWeight(BluetoothUUIDFormatter.isHighlighted(entry.serviceUUID) ? .bold : .regular)
                            Text(BluetoothHexFormatter.string(entry.payload)).font(.caption2).monospaced().textSelection(.enabled)
                        }
                    }
                }

                Section("Safety boundary") {
                    Text("This phase only scans, connects, discovers services and characteristics, subscribes to notify/indicate, and receives raw bytes. It performs no writes, Huawei authentication, bonding, unpairing, reset, background reconnect, or Spotify control from BLE.")
                        .font(.caption).foregroundStyle(.secondary)
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
        Task {
            let entries = await controller.logSnapshot()
            await MainActor.run { logEntries = entries }
        }
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
