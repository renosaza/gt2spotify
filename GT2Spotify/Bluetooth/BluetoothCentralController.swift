import Combine
import CoreBluetooth
import Foundation

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
        self.logStore = logStore
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

    func connect(id: UUID) {
        guard let peripheral = peripherals[id] else { return }
        stopScan()
        statusMessage = "Connecting to \(peripheral.name ?? id.uuidString)"
        central.connect(peripheral)
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
            let characteristics = (service.characteristics ?? []).map { characteristic in
                BluetoothCharacteristicSnapshot(
                    id: "\(serviceUUID)/\(BluetoothUUIDFormatter.string(characteristic.uuid))",
                    uuid: BluetoothUUIDFormatter.string(characteristic.uuid),
                    properties: propertyNames(characteristic.properties),
                    isNotifying: characteristic.isNotifying
                )
            }
            return BluetoothServiceSnapshot(id: serviceUUID, uuid: serviceUUID, characteristics: characteristics)
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
        Task { @MainActor in
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
            if central.state != .poweredOn { isScanning = false }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let id = peripheral.identifier
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let summary = BluetoothAdvertisementFormatter.summary(advertisementData)
        Task { @MainActor in
            peripherals[id] = peripheral
            registry.ingest(id: id, name: name, rssi: RSSI.intValue, advertisementSummary: summary, seenAt: Date())
            discovered = registry.sorted
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            peripheral.delegate = self
            connectedPeripheral = registry.values[peripheral.identifier] ?? DiscoveredPeripheral(id: peripheral.identifier, name: peripheral.name, rssi: 0, advertisementSummary: "", lastSeen: Date())
            services = []
            statusMessage = "Connected; discovering services"
            peripheral.discoverServices(nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in statusMessage = "Connection failed: \(error?.localizedDescription ?? "unknown error")" }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            connectedPeripheral = nil
            services = []
            statusMessage = error.map { "Disconnected: \($0.localizedDescription)" } ?? "Disconnected"
        }
    }
}

extension BluetoothCentralController: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            if let error { statusMessage = "Service discovery failed: \(error.localizedDescription)"; return }
            for service in peripheral.services ?? [] { peripheral.discoverCharacteristics(nil, for: service) }
            rebuildServices(for: peripheral)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            if let error { statusMessage = "Characteristic discovery failed: \(error.localizedDescription)"; return }
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
        Task { @MainActor in
            if let error { statusMessage = "Notify subscription failed: \(error.localizedDescription)" }
            rebuildServices(for: peripheral)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let value = characteristic.value else { return }
        Task { @MainActor in
            let serviceUUID = serviceByCharacteristic[ObjectIdentifier(characteristic)] ?? characteristic.service.map { BluetoothUUIDFormatter.string($0.uuid) } ?? "UNKNOWN"
            let entry = BluetoothLogEntry(
                peripheralID: peripheral.identifier,
                serviceUUID: serviceUUID,
                characteristicUUID: BluetoothUUIDFormatter.string(characteristic.uuid),
                payload: value
            )
            await logStore.append(entry)
        }
    }
}
