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

    var shortIdentifier: String {
        String(id.uuidString.replacingOccurrences(of: "-", with: "").suffix(6)).uppercased()
    }

    var displayName: String {
        name?.isEmpty == false ? name! : "Unknown • \(shortIdentifier)"
    }

    var watchPriority: Int {
        let value = displayName.lowercased()
        return value.contains("huawei") || value.contains("watch") || value.contains("gt 2") ? 0 : 1
    }
}

struct ConnectedPeripheralCandidate: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String?
    var matchedServiceUUIDs: [String]
    var isRemembered: Bool

    var shortIdentifier: String {
        String(id.uuidString.replacingOccurrences(of: "-", with: "").suffix(6)).uppercased()
    }

    var displayName: String {
        name?.isEmpty == false ? name! : "Unknown • \(shortIdentifier)"
    }

    var watchPriority: Int {
        let value = displayName.lowercased()
        return value.contains("huawei") || value.contains("watch") || value.contains("gt 2") ? 0 : 1
    }
}

struct ConnectedPeripheralCandidateRegistry: Sendable {
    private(set) var values: [UUID: ConnectedPeripheralCandidate] = [:]

    mutating func ingest(id: UUID, name: String?, serviceUUID: String, isRemembered: Bool) {
        if var current = values[id] {
            current.name = name ?? current.name
            if !current.matchedServiceUUIDs.contains(serviceUUID) {
                current.matchedServiceUUIDs.append(serviceUUID)
                current.matchedServiceUUIDs.sort()
            }
            current.isRemembered = current.isRemembered || isRemembered
            values[id] = current
        } else {
            values[id] = ConnectedPeripheralCandidate(
                id: id,
                name: name,
                matchedServiceUUIDs: [serviceUUID],
                isRemembered: isRemembered
            )
        }
    }

    var sorted: [ConnectedPeripheralCandidate] {
        values.values.sorted {
            if $0.isRemembered != $1.isRemembered { return $0.isRemembered }
            if $0.watchPriority != $1.watchPriority { return $0.watchPriority < $1.watchPriority }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
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
        self.id = id
        self.timestamp = timestamp
        self.peripheralID = peripheralID
        self.serviceUUID = serviceUUID
        self.characteristicUUID = characteristicUUID
        self.payload = payload
    }
}

enum BluetoothKnownServices {
    static let connectedProbeUUIDStrings = ["FE01", "FE02"]
    static var connectedProbeUUIDs: [CBUUID] { connectedProbeUUIDStrings.map(CBUUID.init(string:)) }
}

enum BluetoothUUIDFormatter {
    static func string(_ uuid: CBUUID) -> String { uuid.uuidString.uppercased() }
    static func isHighlighted(_ value: String) -> Bool {
        let normalized = value.replacingOccurrences(of: "0x", with: "", options: .caseInsensitive).uppercased()
        return BluetoothKnownServices.connectedProbeUUIDStrings.contains(normalized)
    }
}

enum BluetoothHexFormatter {
    static func string(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
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
            current.name = name ?? current.name
            current.rssi = rssi
            current.advertisementSummary = advertisementSummary
            current.lastSeen = seenAt
            values[id] = current
        } else {
            values[id] = DiscoveredPeripheral(
                id: id,
                name: name,
                rssi: rssi,
                advertisementSummary: advertisementSummary,
                lastSeen: seenAt
            )
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
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return entries.map {
            "\(formatter.string(from: $0.timestamp)) peripheral=\($0.peripheralID.uuidString) service=\($0.serviceUUID) characteristic=\($0.characteristicUUID) length=\($0.payload.count)\n\(BluetoothHexFormatter.string($0.payload))"
        }.joined(separator: "\n\n")
    }
}

@MainActor
final class BluetoothCentralController: NSObject, ObservableObject {
    @Published private(set) var state: CBManagerState = .unknown
    @Published private(set) var isScanning = false
    @Published private(set) var discovered: [DiscoveredPeripheral] = []
    @Published private(set) var connectedCandidates: [ConnectedPeripheralCandidate] = []
    @Published private(set) var rememberedPeripheralID: UUID?
    @Published private(set) var rememberedPeripheral: DiscoveredPeripheral?
    @Published private(set) var connectedPeripheral: DiscoveredPeripheral?
    @Published private(set) var services: [BluetoothServiceSnapshot] = []
    @Published private(set) var statusMessage = "Bluetooth is initializing"

    let logStore: BluetoothLogStore

    private static let rememberedPeripheralKey = "bluetooth.rememberedPeripheralID"
    private let userDefaults: UserDefaults
    private var central: CBCentralManager!
    private var registry = DiscoveredPeripheralRegistry()
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var serviceByCharacteristic: [ObjectIdentifier: String] = [:]

    init(logStore: BluetoothLogStore = BluetoothLogStore(), userDefaults: UserDefaults = .standard) {
        self.logStore = logStore
        self.userDefaults = userDefaults
        self.rememberedPeripheralID = userDefaults.string(forKey: Self.rememberedPeripheralKey).flatMap(UUID.init(uuidString:))
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func startScan() {
        guard state == .poweredOn else {
            statusMessage = "Bluetooth must be powered on before scanning"
            return
        }
        registry = DiscoveredPeripheralRegistry()
        discovered = []
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        isScanning = true
        statusMessage = "Scanning for nearby BLE peripherals"
    }

    func stopScan() {
        central.stopScan()
        isScanning = false
        statusMessage = "Scan stopped"
    }

    func refreshKnownDevices() {
        guard state == .poweredOn else {
            statusMessage = "Bluetooth must be powered on before checking connected devices"
            return
        }
        refreshRememberedPeripheral()
        refreshConnectedCandidates()
        statusMessage = connectedCandidates.isEmpty
            ? "No system-connected peripherals matched FE01 or FE02"
            : "Found \(connectedCandidates.count) system-connected BLE candidate(s)"
    }

    func connect(id: UUID) {
        if peripherals[id] == nil { refreshRememberedPeripheral() }
        guard let peripheral = peripherals[id] else {
            statusMessage = "Device is not currently retrievable; scan or refresh connected devices"
            return
        }
        stopScan()
        statusMessage = "Connecting to \(peripheral.name ?? id.uuidString)"
        central.connect(peripheral)
    }

    func disconnect() {
        guard let id = connectedPeripheral?.id, let peripheral = peripherals[id] else { return }
        central.cancelPeripheralConnection(peripheral)
    }

    func remember(id: UUID) {
        rememberedPeripheralID = id
        userDefaults.set(id.uuidString, forKey: Self.rememberedPeripheralKey)
        refreshRememberedPeripheral()
        refreshConnectedCandidates()
        statusMessage = "Remembered \(id.uuidString) as the watch"
    }

    func forgetRememberedPeripheral() {
        rememberedPeripheralID = nil
        rememberedPeripheral = nil
        userDefaults.removeObject(forKey: Self.rememberedPeripheralKey)
        refreshConnectedCandidates()
        statusMessage = "Forgot the saved watch identifier"
    }

    func connectionStateText(id: UUID) -> String {
        switch peripherals[id]?.state {
        case .connected: "Connected"
        case .connecting: "Connecting"
        case .disconnecting: "Disconnecting"
        case .disconnected: "Disconnected"
        case .none: "Not currently retrievable"
        @unknown default: "Unknown"
        }
    }

    func clearLog() async { await logStore.clear() }
    func logSnapshot() async -> [BluetoothLogEntry] { await logStore.snapshot() }
    func exportText() async -> String { await logStore.exportText() }

    private func refreshConnectedCandidates() {
        var candidateRegistry = ConnectedPeripheralCandidateRegistry()
        for service in BluetoothKnownServices.connectedProbeUUIDs {
            let serviceUUID = BluetoothUUIDFormatter.string(service)
            for peripheral in central.retrieveConnectedPeripherals(withServices: [service]) {
                peripherals[peripheral.identifier] = peripheral
                candidateRegistry.ingest(
                    id: peripheral.identifier,
                    name: peripheral.name,
                    serviceUUID: serviceUUID,
                    isRemembered: peripheral.identifier == rememberedPeripheralID
                )
            }
        }
        connectedCandidates = candidateRegistry.sorted
    }

    private func refreshRememberedPeripheral() {
        guard let id = rememberedPeripheralID else {
            rememberedPeripheral = nil
            return
        }

        if let peripheral = central.retrievePeripherals(withIdentifiers: [id]).first {
            peripherals[id] = peripheral
            if let discoveredValue = registry.values[id] {
                rememberedPeripheral = discoveredValue
            } else {
                rememberedPeripheral = DiscoveredPeripheral(
                    id: id,
                    name: peripheral.name,
                    rssi: 0,
                    advertisementSummary: "Saved iOS identifier; state=\(connectionStateText(id: id))",
                    lastSeen: Date()
                )
            }
        } else {
            rememberedPeripheral = DiscoveredPeripheral(
                id: id,
                name: nil,
                rssi: 0,
                advertisementSummary: "Saved iOS identifier is not currently retrievable",
                lastSeen: Date()
            )
        }
    }

    private func rebuildServices(for peripheral: CBPeripheral) {
        services = (peripheral.services ?? []).map { service in
            let serviceUUID = BluetoothUUIDFormatter.string(service.uuid)
            return BluetoothServiceSnapshot(
                id: serviceUUID,
                uuid: serviceUUID,
                characteristics: (service.characteristics ?? []).map {
                    BluetoothCharacteristicSnapshot(
                        id: "\(serviceUUID)/\(BluetoothUUIDFormatter.string($0.uuid))",
                        uuid: BluetoothUUIDFormatter.string($0.uuid),
                        properties: propertyNames($0.properties),
                        isNotifying: $0.isNotifying
                    )
                }
            )
        }
    }

    private func propertyNames(_ properties: CBCharacteristicProperties) -> [String] {
        var result: [String] = []
        if properties.contains(.broadcast) { result.append("broadcast") }
        if properties.contains(.read) { result.append("read") }
        if properties.contains(.writeWithoutResponse) { result.append("writeWithoutResponse") }
        if properties.contains(.write) { result.append("write") }
        if properties.contains(.notify) { result.append("notify") }
        if properties.contains(.indicate) { result.append("indicate") }
        if properties.contains(.authenticatedSignedWrites) { result.append("authenticatedSignedWrites") }
        if properties.contains(.extendedProperties) { result.append("extendedProperties") }
        if properties.contains(.notifyEncryptionRequired) { result.append("notifyEncryptionRequired") }
        if properties.contains(.indicateEncryptionRequired) { result.append("indicateEncryptionRequired") }
        return result
    }
}

extension BluetoothCentralController: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            state = central.state
            statusMessage = switch central.state {
            case .unknown: "Bluetooth state is unknown"
            case .resetting: "Bluetooth is resetting"
            case .unsupported: "Bluetooth LE is unsupported"
            case .unauthorized: "Bluetooth permission is not authorized"
            case .poweredOff: "Bluetooth is powered off"
            case .poweredOn: "Bluetooth is powered on"
            @unknown default: "Unknown Bluetooth state"
            }
            if central.state == .poweredOn {
                refreshKnownDevices()
            } else {
                isScanning = false
                connectedCandidates = []
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let id = peripheral.identifier
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let summary = BluetoothAdvertisementFormatter.summary(advertisementData)
        let rssi = RSSI.intValue
        Task { @MainActor [weak self] in
            guard let self else { return }
            peripherals[id] = peripheral
            registry.ingest(id: id, name: name, rssi: rssi, advertisementSummary: summary, seenAt: Date())
            discovered = registry.sorted
            if id == rememberedPeripheralID { rememberedPeripheral = registry.values[id] }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            peripheral.delegate = self
            connectedPeripheral = registry.values[peripheral.identifier] ?? DiscoveredPeripheral(
                id: peripheral.identifier,
                name: peripheral.name,
                rssi: 0,
                advertisementSummary: "Connected without scan metadata",
                lastSeen: Date()
            )
            services = []
            statusMessage = "Connected; discovering services"
            peripheral.discoverServices(nil)
            refreshKnownDevices()
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor [weak self] in
            self?.statusMessage = "Connection failed: \(error?.localizedDescription ?? "unknown error")"
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            connectedPeripheral = nil
            services = []
            statusMessage = error.map { "Disconnected: \($0.localizedDescription)" } ?? "Disconnected"
            refreshKnownDevices()
        }
    }
}

extension BluetoothCentralController: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let error {
                statusMessage = "Service discovery failed: \(error.localizedDescription)"
                return
            }
            for service in peripheral.services ?? [] { peripheral.discoverCharacteristics(nil, for: service) }
            rebuildServices(for: peripheral)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let error {
                statusMessage = "Characteristic discovery failed: \(error.localizedDescription)"
                return
            }
            let serviceUUID = BluetoothUUIDFormatter.string(service.uuid)
            for characteristic in service.characteristics ?? [] {
                serviceByCharacteristic[ObjectIdentifier(characteristic)] = serviceUUID
                if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
            rebuildServices(for: peripheral)
            statusMessage = "Services and characteristics discovered"
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor [weak self] in
            if let error { self?.statusMessage = "Notify subscription failed: \(error.localizedDescription)" }
            self?.rebuildServices(for: peripheral)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let value = characteristic.value else { return }
        let peripheralID = peripheral.identifier
        let characteristicUUID = BluetoothUUIDFormatter.string(characteristic.uuid)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let serviceUUID = serviceByCharacteristic[ObjectIdentifier(characteristic)]
                ?? characteristic.service.map { BluetoothUUIDFormatter.string($0.uuid) }
                ?? "UNKNOWN"
            await logStore.append(
                BluetoothLogEntry(
                    peripheralID: peripheralID,
                    serviceUUID: serviceUUID,
                    characteristicUUID: characteristicUUID,
                    payload: value
                )
            )
        }
    }
}
