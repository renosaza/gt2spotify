import Foundation
import XCTest
@testable import GT2Spotify

func response(
    _ request: URLRequest,
    status: Int,
    headers: [String: String]? = nil,
    body: String = ""
) -> (HTTPURLResponse, Data) {
    let response = HTTPURLResponse(
        url: request.url!,
        statusCode: status,
        httpVersion: nil,
        headerFields: headers
    )!
    return (response, Data(body.utf8))
}

final class BluetoothDiscoveryTests: XCTestCase {
    func testDuplicateScanUpdatesExistingPeripheral() {
        let id = UUID(); let first = Date(timeIntervalSince1970: 1); let second = Date(timeIntervalSince1970: 2)
        var registry = DiscoveredPeripheralRegistry()
        registry.ingest(id: id, name: "HUAWEI WATCH GT 2", rssi: -80, advertisementSummary: "first", seenAt: first)
        registry.ingest(id: id, name: nil, rssi: -45, advertisementSummary: "second", seenAt: second)
        XCTAssertEqual(registry.values.count, 1)
        XCTAssertEqual(registry.values[id]?.name, "HUAWEI WATCH GT 2")
        XCTAssertEqual(registry.values[id]?.rssi, -45)
        XCTAssertEqual(registry.values[id]?.lastSeen, second)
    }

    func testWatchNamesSortBeforeStrongerGenericDevice() {
        var registry = DiscoveredPeripheralRegistry()
        registry.ingest(id: UUID(), name: "Speaker", rssi: -20, advertisementSummary: "", seenAt: Date())
        registry.ingest(id: UUID(), name: "Huawei Watch", rssi: -90, advertisementSummary: "", seenAt: Date())
        XCTAssertEqual(registry.sorted.first?.displayName, "Huawei Watch")
    }

    func testRSSISortsDescendingAtSamePriority() {
        var registry = DiscoveredPeripheralRegistry()
        registry.ingest(id: UUID(), name: "Device A", rssi: -80, advertisementSummary: "", seenAt: Date())
        registry.ingest(id: UUID(), name: "Device B", rssi: -30, advertisementSummary: "", seenAt: Date())
        XCTAssertEqual(registry.sorted.first?.rssi, -30)
    }

    func testHexFormatting() {
        XCTAssertEqual(BluetoothHexFormatter.string(Data([0x00, 0x0A, 0xFF])), "00 0A FF")
        XCTAssertEqual(BluetoothHexFormatter.string(Data()), "")
    }

    func testHighlightedUUIDsAreCaseInsensitive() {
        XCTAssertTrue(BluetoothUUIDFormatter.isHighlighted("fe01"))
        XCTAssertTrue(BluetoothUUIDFormatter.isHighlighted("0xFE02"))
        XCTAssertFalse(BluetoothUUIDFormatter.isHighlighted("180F"))
    }

    func testAdvertisementSummaryHandlesUnknownValues() {
        let summary = BluetoothAdvertisementFormatter.summary(["custom": NSObject(), "number": 7])
        XCTAssertTrue(summary.contains("custom="))
        XCTAssertTrue(summary.contains("number=7"))
    }

    func testBoundedLogDropsOldestEntries() async {
        let store = BluetoothLogStore(capacity: 2); let peripheral = UUID()
        await store.append(BluetoothLogEntry(id: UUID(), peripheralID: peripheral, serviceUUID: "1", characteristicUUID: "A", payload: Data([1])))
        let second = BluetoothLogEntry(id: UUID(), peripheralID: peripheral, serviceUUID: "2", characteristicUUID: "B", payload: Data([2]))
        let third = BluetoothLogEntry(id: UUID(), peripheralID: peripheral, serviceUUID: "3", characteristicUUID: "C", payload: Data([3]))
        await store.append(second); await store.append(third)
        let entries = await store.snapshot()
        XCTAssertEqual(entries.map(\.id), [second.id, third.id])
    }
}
