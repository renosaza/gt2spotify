import CoreBluetooth
import Foundation

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

struct BluetoothServiceSnapshot: Identifiable, Equatable, Sendable {
    let id: String
    let uuid: String
    var characteristics: [BluetoothCharacteristicSnapshot]
}

struct BluetoothCharacteristicSnapshot: Identifiable, Equatable, Sendable {
    let id: String
    let uuid: String
    let properties: [String]
    let isNotifying: Bool
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

enum BluetoothUUIDFormatter {
    static func string(_ uuid: CBUUID) -> String { uuid.uuidString.uppercased() }
    static func isHighlighted(_ value: String) -> Bool {
        let normalized = value.replacingOccurrences(of: "0x", with: "", options: .caseInsensitive).uppercased()
        return normalized == "FE01" || normalized == "FE02"
    }
}

enum BluetoothHexFormatter {
    static func string(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

enum BluetoothAdvertisementFormatter {
    static func summary(_ advertisementData: [String: Any]) -> String {
        advertisementData.keys.sorted().map { key in
            let value = advertisementData[key]
            if let data = value as? Data { return "\(key)=\(BluetoothHexFormatter.string(data))" }
            if let uuids = value as? [CBUUID] { return "\(key)=\(uuids.map(\.uuidString).joined(separator: ","))" }
            return "\(key)=\(String(describing: value ?? "nil"))"
        }.joined(separator: "; ")
    }
}

struct DiscoveredPeripheralRegistry: Sendable {
    private(set) var values: [UUID: DiscoveredPeripheral] = [:]

    mutating func ingest(id: UUID, name: String?, rssi: Int, advertisementSummary: String, seenAt: Date) {
        if var existing = values[id] {
            existing.name = name ?? existing.name
            existing.rssi = rssi
            existing.advertisementSummary = advertisementSummary
            existing.lastSeen = seenAt
            values[id] = existing
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
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return entries.map {
            "\(formatter.string(from: $0.timestamp)) peripheral=\($0.peripheralID.uuidString) service=\($0.serviceUUID) characteristic=\($0.characteristicUUID) length=\($0.payload.count)\n\(BluetoothHexFormatter.string($0.payload))"
        }.joined(separator: "\n\n")
    }
}
