import ExternalAccessory
import MediaPlayer
import SwiftUI
@preconcurrency import CoreBluetooth
import UniformTypeIdentifiers
import UIKit

@MainActor
struct DashboardView: View {
    @StateObject private var viewModel: DashboardViewModel
    @Environment(\.openURL) private var openURL

    init(viewModel: DashboardViewModel) { _viewModel = StateObject(wrappedValue: viewModel) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Spotify authorization") {
                    LabeledContent("Configured", value: viewModel.isConfigured ? "Yes" : "No")
                    LabeledContent("Token in Keychain", value: viewModel.isAuthorized ? "Yes" : "No")
                    Button("Connect Spotify") { viewModel.connectSpotify() }
                        .disabled(viewModel.isBusy || !viewModel.isConfigured)
                    Button("Open Spotify") { if let url = URL(string: "spotify://") { openURL(url) } }
                }
                Section("Playback") {
                    if let playback = viewModel.playback {
                        Text(playback.track).font(.headline)
                        Text(playback.artist).foregroundStyle(.secondary)
                        LabeledContent("State", value: playback.isPlaying ? "Playing" : "Paused")
                        LabeledContent("Device", value: playback.deviceName ?? "Unknown")
                    } else {
                        Text("No playback snapshot loaded").foregroundStyle(.secondary)
                    }
                    HStack {
                        Button { viewModel.perform(.previous) } label: { Image(systemName: "backward.fill") }
                        Spacer()
                        Button { viewModel.perform(.play) } label: { Image(systemName: "play.fill") }
                        Spacer()
                        Button { viewModel.perform(.pause) } label: { Image(systemName: "pause.fill") }
                        Spacer()
                        Button { viewModel.perform(.next) } label: { Image(systemName: "forward.fill") }
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isBusy || !viewModel.isAuthorized)
                }
                Section("Volume") {
                    if viewModel.supportsSpotifyVolumeControl {
                        Slider(value: $viewModel.volume, in: 0...100, step: 1)
                        Button("Set volume to \(Int(viewModel.volume))%") { viewModel.setAbsoluteVolume() }
                    } else if viewModel.shouldUseSystemVolumeControl {
                        SystemVolumeControl().frame(minHeight: 44)
                    } else {
                        Text("Refresh playback to determine volume support.").foregroundStyle(.secondary)
                    }
                }
                Section("Diagnostics") {
                    Text(viewModel.statusMessage)
                    Button("Refresh playback and devices") { viewModel.refresh() }
                        .disabled(viewModel.isBusy || !viewModel.isAuthorized)
                }
                Section("Huawei") {
                    Text("Transport Gate 0 is in the Bluetooth tab. No Huawei authentication or writes are implemented.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("GT2Spotify")
            .overlay { if viewModel.isBusy { ProgressView().controlSize(.large) } }
        }
    }
}

private struct SystemVolumeControl: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.showsRouteButton = false
        return view
    }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

@MainActor
struct BluetoothDashboardView: View {
    @StateObject private var probe = TransportFeasibilityController()
    @State private var exportDocument: BluetoothLogDocument?
    @State private var exportType: UTType = .plainText
    @State private var exportFilename = "gt2-transport-feasibility.md"

    init(controller: BluetoothCentralController) { _ = controller }

    var body: some View {
        NavigationStack {
            List {
                Section("Transport feasibility — Gate 0") {
                    LabeledContent("Verdict", value: probe.verdict.rawValue)
                    LabeledContent("iOS", value: UIDevice.current.systemVersion)
                    LabeledContent("Model", value: UIDevice.current.model)
                    LabeledContent("Bluetooth", value: probe.stateText)
                    LabeledContent("Authorization", value: probe.authorizationText)
                    Text(probe.statusMessage).font(.caption).foregroundStyle(.secondary)

                    ForEach(TransportScanMode.allCases) { mode in
                        Button("Scan: \(mode.rawValue)") { probe.startScan(mode) }
                            .disabled(probe.state != .poweredOn || probe.isScanning)
                    }
                    Button("Stop scan") { probe.stopScan() }.disabled(!probe.isScanning)
                    Button("Retrieve remembered watch") { probe.retrieveRemembered() }
                        .disabled(probe.rememberedIdentifier == nil)
                    Button("Refresh ExternalAccessory") { probe.refreshExternalAccessories() }

                    HStack {
                        Button("Export Markdown") {
                            exportDocument = BluetoothLogDocument(text: probe.markdown())
                            exportType = .plainText
                            exportFilename = "gt2-transport-feasibility.md"
                        }
                        Button("Export JSON") {
                            do {
                                exportDocument = BluetoothLogDocument(text: try probe.json())
                                exportType = .json
                                exportFilename = "gt2-transport-feasibility.json"
                            } catch { probe.setError(error) }
                        }
                    }
                }

                Section("CoreBluetooth observations") {
                    if probe.peripherals.isEmpty {
                        Text("No peripherals observed in this scan mode.").foregroundStyle(.secondary)
                    }
                    ForEach(probe.peripherals) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.displayName).font(.headline)
                            Text(item.id.uuidString).font(.caption2).textSelection(.enabled)
                            LabeledContent("RSSI", value: "\(item.rssi) dBm")
                            LabeledContent("State", value: probe.connectionState(id: item.id))
                            LabeledContent("ANCS", value: item.ancsAuthorized.map { $0 ? "Authorized" : "Not authorized" } ?? "Unknown")
                            if !item.advertisement.isEmpty {
                                Text(item.advertisement).font(.caption2).foregroundStyle(.secondary)
                            }
                            HStack {
                                Button("Remember") { probe.remember(item.id) }
                                Button("Connect read-only") { probe.connect(item.id, requiresANCS: false) }
                                Button("Connect + ANCS") { probe.connect(item.id, requiresANCS: true) }
                            }
                        }
                    }
                    if probe.connectedIdentifier != nil {
                        Button("Disconnect", role: .destructive) { probe.disconnect() }
                    }
                }

                Section("GATT service dump") {
                    if probe.services.isEmpty { Text("No services discovered.").foregroundStyle(.secondary) }
                    ForEach(probe.services) { service in
                        DisclosureGroup {
                            ForEach(service.characteristics) { characteristic in
                                VStack(alignment: .leading) {
                                    Text(characteristic.uuid).monospaced()
                                    Text(characteristic.properties.joined(separator: ", "))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        } label: { Text(service.uuid).monospaced() }
                    }
                }

                Section("ExternalAccessory inventory") {
                    if probe.accessories.isEmpty {
                        Text("No accessory is exposed through ExternalAccessory.").foregroundStyle(.secondary)
                    }
                    ForEach(probe.accessories) { accessory in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(accessory.name).font(.headline)
                            Text("\(accessory.manufacturer) • \(accessory.modelNumber)").font(.caption)
                            LabeledContent("Firmware", value: accessory.firmwareRevision)
                            LabeledContent("Hardware", value: accessory.hardwareRevision)
                            LabeledContent("Protocols", value: accessory.protocolStrings.isEmpty ? "None" : accessory.protocolStrings.joined(separator: ", "))
                        }
                    }
                }

                Section("Safety boundary") {
                    Text("This screen scans, retrieves a saved CoreBluetooth identifier, connects, discovers GATT metadata, observes ANCS authorization, inventories ExternalAccessory, and exports redacted evidence. It performs no characteristic reads or writes, subscriptions, EASession creation, Huawei authentication, reset, unpair, or bond removal.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Transport bridging requests existing system classic profiles; it is not treated as an app-visible RFCOMM socket.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Bluetooth")
            .fileExporter(
                isPresented: Binding(get: { exportDocument != nil }, set: { if !$0 { exportDocument = nil } }),
                document: exportDocument,
                contentType: exportType,
                defaultFilename: exportFilename
            ) { _ in exportDocument = nil }
        }
    }
}

enum TransportFeasibilityVerdict: String, Codable, Sendable {
    case feasibleBLEGATT = "FEASIBLE_BLE_GATT"
    case feasibleBREDRGATT = "FEASIBLE_BR_EDR_GATT"
    case feasibleExternalAccessory = "FEASIBLE_EXTERNAL_ACCESSORY"
    case blockedPrivateRFCOMM = "BLOCKED_PRIVATE_RFCOMM"
    case unknownNeedsMoreEvidence = "UNKNOWN_NEEDS_MORE_EVIDENCE"
}

enum TransportScanMode: String, CaseIterable, Identifiable, Sendable {
    case all = "All BLE advertisements"
    case fe86 = "FE86 GATT service"
    case huaweiSDP = "82FF… SDP UUID as GATT"
    var id: String { rawValue }
    var serviceStrings: [String]? {
        switch self {
        case .all: nil
        case .fe86: ["FE86"]
        case .huaweiSDP: ["82FF3820-8411-400C-B85A-55BDB32CF060"]
        }
    }
    var services: [CBUUID]? { serviceStrings?.map(CBUUID.init(string:)) }
}

struct TransportPeripheral: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var name: String?
    var rssi: Int
    var advertisement: String
    var ancsAuthorized: Bool?
    var displayName: String { name?.isEmpty == false ? name! : "Unknown • \(id.uuidString.suffix(6))" }
}

struct TransportCharacteristic: Identifiable, Equatable, Codable, Sendable {
    let id: String
    let uuid: String
    let properties: [String]
}

struct TransportService: Identifiable, Equatable, Codable, Sendable {
    let id: String
    let uuid: String
    let characteristics: [TransportCharacteristic]
}

struct TransportAccessory: Identifiable, Equatable, Codable, Sendable {
    let id: Int
    let name: String
    let manufacturer: String
    let modelNumber: String
    let firmwareRevision: String
    let hardwareRevision: String
    let protocolStrings: [String]
    let isConnected: Bool
}

struct TransportReport: Equatable, Codable, Sendable {
    let generatedAt: String
    let verdict: TransportFeasibilityVerdict
    let iOSVersion: String
    let model: String
    let xcodeBuild: String
    let sdkName: String
    let bluetoothState: String
    let bluetoothAuthorization: String
    let scanMode: String?
    let rememberedIdentifier: UUID?
    let connectedIdentifier: UUID?
    let peripherals: [TransportPeripheral]
    let services: [TransportService]
    let accessories: [TransportAccessory]
    let notes: [String]
}

enum TransportReportFormatter {
    static func json(_ report: TransportReport) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(report), as: UTF8.self)
    }

    static func markdown(_ report: TransportReport) -> String {
        let peripherals = report.peripherals.isEmpty ? "- None" : report.peripherals.map {
            "- `\($0.id)` — \($0.displayName), RSSI \($0.rssi), ANCS \($0.ancsAuthorized.map(String.init) ?? "unknown")\n  - \($0.advertisement.isEmpty ? "no advertisement data" : $0.advertisement)"
        }.joined(separator: "\n")
        let services = report.services.isEmpty ? "- None" : report.services.map { service in
            let chars = service.characteristics.map { "  - `\($0.uuid)` [\($0.properties.joined(separator: ", "))]" }.joined(separator: "\n")
            return "- `\(service.uuid)`\n\(chars.isEmpty ? "  - no characteristics" : chars)"
        }.joined(separator: "\n")
        let accessories = report.accessories.isEmpty ? "- None" : report.accessories.map {
            "- \($0.name) — \($0.manufacturer) \($0.modelNumber); protocols: \($0.protocolStrings.isEmpty ? "none" : $0.protocolStrings.joined(separator: ", "))"
        }.joined(separator: "\n")
        return """
        # Huawei GT2 iOS transport feasibility

        Generated: \(report.generatedAt)

        ## Verdict
        `\(report.verdict.rawValue)`

        The verdict stays unknown until a physical iPhone and Huawei Watch GT2 test produces transport evidence. Simulator CI is not Bluetooth evidence.

        ## System
        - iOS: \(report.iOSVersion)
        - Model: \(report.model)
        - Xcode build: \(report.xcodeBuild)
        - SDK: \(report.sdkName)
        - Bluetooth: \(report.bluetoothState)
        - Authorization: \(report.bluetoothAuthorization)
        - Scan mode: \(report.scanMode ?? "none")
        - Remembered: \(report.rememberedIdentifier?.uuidString ?? "none")
        - Connected: \(report.connectedIdentifier?.uuidString ?? "none")

        ## CoreBluetooth
        \(peripherals)

        ## GATT
        \(services)

        ## ExternalAccessory
        \(accessories)

        ## Notes
        \(report.notes.map { "- \($0)" }.joined(separator: "\n"))

        ## Redaction
        No Spotify token, Huawei key, notification body, Apple Account data, or raw secret payload is included.
        """
    }
}

@MainActor
final class TransportFeasibilityController: NSObject, ObservableObject {
    @Published private(set) var state: CBManagerState = .unknown
    @Published private(set) var isScanning = false
    @Published private(set) var scanMode: TransportScanMode?
    @Published private(set) var peripherals: [TransportPeripheral] = []
    @Published private(set) var connectedIdentifier: UUID?
    @Published private(set) var services: [TransportService] = []
    @Published private(set) var accessories: [TransportAccessory] = []
    @Published private(set) var verdict: TransportFeasibilityVerdict = .unknownNeedsMoreEvidence
    @Published private(set) var statusMessage = "Initializing"

    private static let rememberedKey = "bluetooth.rememberedPeripheralID"
    private var central: CBCentralManager!
    private var objects: [UUID: CBPeripheral] = [:]

    var rememberedIdentifier: UUID? {
        UserDefaults.standard.string(forKey: Self.rememberedKey).flatMap(UUID.init(uuidString:))
    }
    var stateText: String { Self.stateText(state) }
    var authorizationText: String {
        switch CBCentralManager.authorization {
        case .notDetermined: "Not determined"
        case .restricted: "Restricted"
        case .denied: "Denied"
        case .allowedAlways: "Allowed always"
        @unknown default: "Unknown"
        }
    }

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
        refreshExternalAccessories()
    }

    func startScan(_ mode: TransportScanMode) {
        guard state == .poweredOn else { statusMessage = "Bluetooth is not powered on"; return }
        central.stopScan()
        objects = [:]
        peripherals = []
        services = []
        scanMode = mode
        central.scanForPeripherals(withServices: mode.services, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        isScanning = true
        statusMessage = "Scanning: \(mode.rawValue)"
    }

    func stopScan() { central.stopScan(); isScanning = false; statusMessage = "Scan stopped" }

    func remember(_ id: UUID) {
        UserDefaults.standard.set(id.uuidString, forKey: Self.rememberedKey)
        objectWillChange.send()
        statusMessage = "Remembered CoreBluetooth identifier"
    }

    func retrieveRemembered() {
        guard let id = rememberedIdentifier else { statusMessage = "No remembered identifier"; return }
        guard let peripheral = central.retrievePeripherals(withIdentifiers: [id]).first else {
            statusMessage = "Remembered identifier is not currently retrievable"; return
        }
        objects[id] = peripheral
        upsert(id, peripheral.name, 0, "Retrieved from saved CoreBluetooth identifier", peripheral.ancsAuthorized)
    }

    func connect(_ id: UUID, requiresANCS: Bool) {
        guard let peripheral = objects[id] else { statusMessage = "Peripheral is not retrievable"; return }
        stopScan()
        let options: [String: Any]? = requiresANCS ? [
            CBConnectPeripheralOptionRequiresANCS: true,
            CBConnectPeripheralOptionEnableTransportBridgingKey: true
        ] : nil
        statusMessage = requiresANCS ? "Connecting with ANCS and transport bridging requested" : "Connecting read-only"
        central.connect(peripheral, options: options)
    }

    func disconnect() {
        guard let id = connectedIdentifier, let peripheral = objects[id] else { return }
        central.cancelPeripheralConnection(peripheral)
    }

    func connectionState(id: UUID) -> String {
        switch objects[id]?.state {
        case .connected: "Connected"
        case .connecting: "Connecting"
        case .disconnecting: "Disconnecting"
        case .disconnected: "Disconnected"
        case .none: "Not retrievable"
        @unknown default: "Unknown"
        }
    }

    func refreshExternalAccessories() {
        accessories = EAAccessoryManager.shared().connectedAccessories.map {
            TransportAccessory(
                id: $0.connectionID, name: $0.name, manufacturer: $0.manufacturer,
                modelNumber: $0.modelNumber, firmwareRevision: $0.firmwareRevision,
                hardwareRevision: $0.hardwareRevision, protocolStrings: $0.protocolStrings.sorted(),
                isConnected: $0.isConnected
            )
        }
    }

    func report() -> TransportReport {
        let date = ISO8601DateFormatter().string(from: Date())
        return TransportReport(
            generatedAt: date, verdict: verdict, iOSVersion: UIDevice.current.systemVersion,
            model: UIDevice.current.model,
            xcodeBuild: Bundle.main.object(forInfoDictionaryKey: "DTXcodeBuild") as? String ?? "unavailable",
            sdkName: Bundle.main.object(forInfoDictionaryKey: "DTSDKName") as? String ?? "unavailable",
            bluetoothState: stateText, bluetoothAuthorization: authorizationText,
            scanMode: scanMode?.rawValue, rememberedIdentifier: rememberedIdentifier,
            connectedIdentifier: connectedIdentifier, peripherals: peripherals,
            services: services, accessories: accessories,
            notes: [
                "FE86 is tested only as GATT; it is not assumed equivalent to Gadgetbridge Huawei BR transport.",
                "82FF3820-8411-400C-B85A-55BDB32CF060 is tested as a GATT filter and accessory clue, not proof of an RFCOMM socket.",
                "Transport bridging requests existing system classic profiles and does not expose a generic serial socket.",
                "No characteristic read/write, subscription, EASession, Huawei auth, reset, unpair, or bond removal is performed."
            ]
        )
    }

    func markdown() -> String { TransportReportFormatter.markdown(report()) }
    func json() throws -> String { try TransportReportFormatter.json(report()) }
    func setError(_ error: Error) { statusMessage = "Export failed: \(error.localizedDescription)" }

    private func upsert(_ id: UUID, _ name: String?, _ rssi: Int, _ advertisement: String, _ ancs: Bool?) {
        if let index = peripherals.firstIndex(where: { $0.id == id }) {
            peripherals[index].name = name ?? peripherals[index].name
            peripherals[index].rssi = rssi
            peripherals[index].advertisement = advertisement
            peripherals[index].ancsAuthorized = ancs ?? peripherals[index].ancsAuthorized
        } else {
            peripherals.append(TransportPeripheral(id: id, name: name, rssi: rssi, advertisement: advertisement, ancsAuthorized: ancs))
        }
        peripherals.sort { $0.rssi == $1.rssi ? $0.displayName < $1.displayName : $0.rssi > $1.rssi }
    }

    private func rebuild(_ peripheral: CBPeripheral) {
        services = (peripheral.services ?? []).map { service in
            let serviceID = service.uuid.uuidString.uppercased()
            return TransportService(
                id: serviceID, uuid: serviceID,
                characteristics: (service.characteristics ?? []).map {
                    let id = $0.uuid.uuidString.uppercased()
                    return TransportCharacteristic(id: "\(serviceID)/\(id)", uuid: id, properties: Self.properties($0.properties))
                }
            )
        }
    }

    private static func properties(_ value: CBCharacteristicProperties) -> [String] {
        var result: [String] = []
        if value.contains(.read) { result.append("read") }
        if value.contains(.write) { result.append("write") }
        if value.contains(.writeWithoutResponse) { result.append("writeWithoutResponse") }
        if value.contains(.notify) { result.append("notify") }
        if value.contains(.indicate) { result.append("indicate") }
        return result
    }

    private static func stateText(_ state: CBManagerState) -> String {
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

extension TransportFeasibilityController: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor [weak self] in
            self?.state = central.state
            self?.statusMessage = "Bluetooth: \(Self.stateText(central.state))"
            if central.state != .poweredOn { self?.isScanning = false }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let id = peripheral.identifier
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let advertisement = BluetoothAdvertisementFormatter.summary(advertisementData)
        let ancs = peripheral.ancsAuthorized
        Task { @MainActor [weak self] in
            self?.objects[id] = peripheral
            self?.upsert(id, name, RSSI.intValue, advertisement, ancs)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            connectedIdentifier = peripheral.identifier
            peripheral.delegate = self
            upsert(peripheral.identifier, peripheral.name, 0, "Connected; discovering services", peripheral.ancsAuthorized)
            statusMessage = "Connected; no characteristic reads, writes, or subscriptions"
            peripheral.discoverServices(nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor [weak self] in self?.statusMessage = "Connection failed: \(error?.localizedDescription ?? "unknown")" }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor [weak self] in
            self?.connectedIdentifier = nil
            self?.services = []
            self?.statusMessage = error.map { "Disconnected: \($0.localizedDescription)" } ?? "Disconnected"
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didUpdateANCSAuthorizationFor peripheral: CBPeripheral) {
        let id = peripheral.identifier
        let authorized = peripheral.ancsAuthorized
        Task { @MainActor [weak self] in
            guard let self, let index = peripherals.firstIndex(where: { $0.id == id }) else { return }
            peripherals[index].ancsAuthorized = authorized
            statusMessage = "ANCS authorization changed: \(authorized)"
        }
    }
}

extension TransportFeasibilityController: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let error { statusMessage = "Service discovery failed: \(error.localizedDescription)"; return }
            for service in peripheral.services ?? [] { peripheral.discoverCharacteristics(nil, for: service) }
            rebuild(peripheral)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let error { statusMessage = "Characteristic discovery failed: \(error.localizedDescription)"; return }
            rebuild(peripheral)
            statusMessage = "Service dump complete; no reads, writes, or subscriptions"
        }
    }
}

struct BluetoothLogDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText, .json] }
    let text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = configuration.file.regularFileContents.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
