import Foundation
import Combine
@preconcurrency import CoreBluetooth

actor MusicBridgeCoordinator {
    private let player: SpotifyPlayerController

    init(player: SpotifyPlayerController) { self.player = player }

    func execute(_ command: MusicCommand) async throws {
        switch command {
        case .play: try await player.play()
        case .pause: try await player.pause()
        case .previous: try await player.previous()
        case .next: try await player.next()
        case .volumeUp: try await player.changeVolume(by: 5)
        case .volumeDown: try await player.changeVolume(by: -5)
        case .setVolume(let value): try await player.setVolume(value)
        }
    }
}

struct DiscoveredPeripheral: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String?
    var rssi: Int
    var advertisementSummary: String
    var lastSeen: Date
    var displayName: String { name?.isEmpty == false ? name! : "Unknown peripheral" }
    var watchPriority: Int {
        let value = displayName.lowercased()
        return value.contains("huawei") || value.contains("watch") || value.contains("gt 2") ? 0 : 1
    }
}

struct BluetoothCharacteristicSnapshot: Identifiable, Equatable, Sendable {
    let id: String
    let uuid: String
    let properties: [String]
    let isNotifying: Bool
}

struct BluetoothServiceSnapshot: Identifiable, Equatable, Sendable {
    let id: String
    let uuid: String
    var characteristics: [BluetoothCharacteristicSnapshot]
}

struct BluetoothLogEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let timestamp: Date
    let peripheralID: UUID
    let serviceUUID: String
    let characteristicUUID: String
    let payload: Data

    init(id: UUID = UUID(), timestamp: Date = Date(), peripheralID: UUID, serviceUUID: String, characteristicUUID: String, payload: Data) {
        self.id = id; self.timestamp = timestamp; self.peripheralID = peripheralID
        self.serviceUUID = serviceUUID; self.characteristicUUID = characteristicUUID; self.payload = payload
    }
}

enum BluetoothUUIDFormatter {
    static func string(_ uuid: CBUUID) -> String { uuid.uuidString.uppercased() }
    static func isHighlighted(_ value: String) -> Bool {
        let normalized = value.replacingOccurrences(of: "0x", with: "", options: .caseInsensitive).uppercased()
        return normalized == "FE01" || normalized == "FE02"
    }
}

enum BluetoothHexFormatter {
    static func string(_ data: Data) -> String { data.map { String(format: "%02X", $0) }.joined(separator: " ") }
}

enum BluetoothAdvertisementFormatter {
    static func summary(_ data: [String: Any]) -> String {
        data.keys.sorted().map { key in
            let value = data[key]
            if let bytes = value as? Data { return "\(key)=\(BluetoothHexFormatter.string(bytes))" }
            if let uuids = value as? [CBUUID] { return "\(key)=\(uuids.map(\.uuidString).joined(separator: ","))" }
            return "\(key)=\(String(describing: value ?? "nil"))"
        }.joined(separator: "; ")
    }
}

struct DiscoveredPeripheralRegistry: Sendable {
    private(set) var values: [UUID: DiscoveredPeripheral] = [:]
    mutating func ingest(id: UUID, name: String?, rssi: Int, advertisementSummary: String, seenAt: Date) {
        if var current = values[id] {
            current.name = name ?? current.name; current.rssi = rssi
            current.advertisementSummary = advertisementSummary; current.lastSeen = seenAt; values[id] = current
        } else {
            values[id] = DiscoveredPeripheral(id: id, name: name, rssi: rssi, advertisementSummary: advertisementSummary, lastSeen: seenAt)
        }
    }
    var sorted: [DiscoveredPeripheral] {
        values.values.sorted {
            if $0.watchPriority != $1.watchPriority { return $0.watchPriority < $1.watchPriority }
            if $0.rssi != $1.rssi { return $0.rssi > $1.rssi }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }
}

actor BluetoothLogStore {
    private let capacity: Int
    private var entries: [BluetoothLogEntry] = []
    init(capacity: Int = 2_000) { self.capacity = max(1, capacity) }
    func append(_ entry: BluetoothLogEntry) {
        entries.append(entry)
        if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
    }
    func snapshot() -> [BluetoothLogEntry] { entries }
    func clear() { entries.removeAll(keepingCapacity: true) }
    func exportText() -> String {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return entries.map { "\(formatter.string(from: $0.timestamp)) peripheral=\($0.peripheralID.uuidString) service=\($0.serviceUUID) characteristic=\($0.characteristicUUID) length=\($0.payload.count)\n\(BluetoothHexFormatter.string($0.payload))" }.joined(separator: "\n\n")
    }
}

@MainActor
final class BluetoothCentralController: NSObject, ObservableObject {
    @Published private(set) var state: CBManagerState = .unknown
    @Published private(set) var isScanning = false
    @Published private(set) var discovered: [DiscoveredPeripheral] = []
    @Published private(set) var connectedPeripheral: DiscoveredPeripheral?
    @Published private(set) var services: [BluetoothServiceSnapshot] = []
    @Published private(set) var statusMessage = "Bluetooth is initializing"

    let logStore: BluetoothLogStore
    private var central: CBCentralManager!
    private var registry = DiscoveredPeripheralRegistry()
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var serviceByCharacteristic: [ObjectIdentifier: String] = [:]

    init(logStore: BluetoothLogStore = BluetoothLogStore()) {
        self.logStore = logStore; super.init(); central = CBCentralManager(delegate: self, queue: nil)
    }

    func startScan() {
        guard state == .poweredOn else { statusMessage = "Bluetooth must be powered on before scanning"; return }
        registry = DiscoveredPeripheralRegistry(); discovered = []
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        isScanning = true; statusMessage = "Scanning for nearby BLE peripherals"
    }
    func stopScan() { central.stopScan(); isScanning = false; statusMessage = "Scan stopped" }
    func connect(id: UUID) {
        guard let peripheral = peripherals[id] else { return }
        stopScan(); statusMessage = "Connecting to \(peripheral.name ?? id.uuidString)"; central.connect(peripheral)
    }
    func disconnect() {
        guard let id = connectedPeripheral?.id, let peripheral = peripherals[id] else { return }
        central.cancelPeripheralConnection(peripheral)
    }
    func clearLog() async { await logStore.clear() }
    func logSnapshot() async -> [BluetoothLogEntry] { await logStore.snapshot() }
    func exportText() async -> String { await logStore.exportText() }

    private func rebuildServices(for peripheral: CBPeripheral) {
        services = (peripheral.services ?? []).map { service in
            let serviceUUID = BluetoothUUIDFormatter.string(service.uuid)
            return BluetoothServiceSnapshot(id: serviceUUID, uuid: serviceUUID, characteristics: (service.characteristics ?? []).map {
                BluetoothCharacteristicSnapshot(id: "\(serviceUUID)/\(BluetoothUUIDFormatter.string($0.uuid))", uuid: BluetoothUUIDFormatter.string($0.uuid), properties: propertyNames($0.properties), isNotifying: $0.isNotifying)
            })
        }
    }
    private func propertyNames(_ p: CBCharacteristicProperties) -> [String] {
        var r: [String] = []
        if p.contains(.broadcast) { r.append("broadcast") }; if p.contains(.read) { r.append("read") }
        if p.contains(.writeWithoutResponse) { r.append("writeWithoutResponse") }; if p.contains(.write) { r.append("write") }
        if p.contains(.notify) { r.append("notify") }; if p.contains(.indicate) { r.append("indicate") }
        if p.contains(.authenticatedSignedWrites) { r.append("authenticatedSignedWrites") }
        if p.contains(.extendedProperties) { r.append("extendedProperties") }
        if p.contains(.notifyEncryptionRequired) { r.append("notifyEncryptionRequired") }
        if p.contains(.indicateEncryptionRequired) { r.append("indicateEncryptionRequired") }
        return r
    }
}

extension BluetoothCentralController: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }; state = central.state
            statusMessage = switch central.state { case .unknown: "Bluetooth state is unknown"; case .resetting: "Bluetooth is resetting"; case .unsupported: "Bluetooth LE is unsupported"; case .unauthorized: "Bluetooth permission is not authorized"; case .poweredOff: "Bluetooth is powered off"; case .poweredOn: "Bluetooth is powered on"; @unknown default: "Unknown Bluetooth state" }
            if central.state != .poweredOn { isScanning = false }
        }
    }
    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let id = peripheral.identifier; let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let summary = BluetoothAdvertisementFormatter.summary(advertisementData); let rssi = RSSI.intValue
        Task { @MainActor [weak self] in self?.peripherals[id] = peripheral; self?.registry.ingest(id: id, name: name, rssi: rssi, advertisementSummary: summary, seenAt: Date()); self?.discovered = self?.registry.sorted ?? [] }
    }
    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor [weak self] in guard let self else { return }; peripheral.delegate = self; connectedPeripheral = registry.values[peripheral.identifier] ?? DiscoveredPeripheral(id: peripheral.identifier, name: peripheral.name, rssi: 0, advertisementSummary: "", lastSeen: Date()); services = []; statusMessage = "Connected; discovering services"; peripheral.discoverServices(nil) }
    }
    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) { Task { @MainActor [weak self] in self?.statusMessage = "Connection failed: \(error?.localizedDescription ?? "unknown error")" } }
    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) { Task { @MainActor [weak self] in self?.connectedPeripheral = nil; self?.services = []; self?.statusMessage = error.map { "Disconnected: \($0.localizedDescription)" } ?? "Disconnected" } }
}

extension BluetoothCentralController: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor [weak self] in guard let self else { return }; if let error { statusMessage = "Service discovery failed: \(error.localizedDescription)"; return }; for service in peripheral.services ?? [] { peripheral.discoverCharacteristics(nil, for: service) }; rebuildServices(for: peripheral) }
    }
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor [weak self] in guard let self else { return }; if let error { statusMessage = "Characteristic discovery failed: \(error.localizedDescription)"; return }; let serviceUUID = BluetoothUUIDFormatter.string(service.uuid); for c in service.characteristics ?? [] { serviceByCharacteristic[ObjectIdentifier(c)] = serviceUUID; if c.properties.contains(.notify) || c.properties.contains(.indicate) { peripheral.setNotifyValue(true, for: c) } }; rebuildServices(for: peripheral); statusMessage = "Services and characteristics discovered" }
    }
    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) { Task { @MainActor [weak self] in if let error { self?.statusMessage = "Notify subscription failed: \(error.localizedDescription)" }; self?.rebuildServices(for: peripheral) } }
    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let value = characteristic.value else { return }
        let peripheralID = peripheral.identifier; let characteristicUUID = BluetoothUUIDFormatter.string(characteristic.uuid)
        Task { @MainActor [weak self] in guard let self else { return }; let serviceUUID = serviceByCharacteristic[ObjectIdentifier(characteristic)] ?? characteristic.service.map { BluetoothUUIDFormatter.string($0.uuid) } ?? "UNKNOWN"; await logStore.append(BluetoothLogEntry(peripheralID: peripheralID, serviceUUID: serviceUUID, characteristicUUID: characteristicUUID, payload: value)) }
    }
}
