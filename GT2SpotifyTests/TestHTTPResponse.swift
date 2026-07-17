import Foundation
import XCTest
import CoreBluetooth
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
    private let noFingerprint = HuaweiFingerprint(score: 0, reasons: [])

    func testDuplicateScanUpdatesExistingPeripheral() {
        let id = UUID()
        let first = Date(timeIntervalSince1970: 1)
        let second = Date(timeIntervalSince1970: 2)
        var registry = DiscoveredPeripheralRegistry()
        registry.ingest(id: id, name: "HUAWEI WATCH GT 2", rssi: -80, advertisementSummary: "first", fingerprint: noFingerprint, seenAt: first)
        registry.ingest(id: id, name: nil, rssi: -45, advertisementSummary: "second", fingerprint: noFingerprint, seenAt: second)
        XCTAssertEqual(registry.values.count, 1)
        XCTAssertEqual(registry.values[id]?.name, "HUAWEI WATCH GT 2")
        XCTAssertEqual(registry.values[id]?.rssi, -45)
        XCTAssertEqual(registry.values[id]?.lastSeen, second)
    }

    func testUnknownPeripheralIncludesStableShortIdentifier() {
        let id = UUID(uuidString: "12345678-1234-1234-1234-123456ABCDEF")!
        let peripheral = DiscoveredPeripheral(
            id: id,
            name: nil,
            rssi: -50,
            advertisementSummary: "",
            lastSeen: Date(),
            fingerprint: noFingerprint
        )
        XCTAssertEqual(peripheral.shortIdentifier, "ABCDEF")
        XCTAssertEqual(peripheral.displayName, "Unknown • ABCDEF")
    }

    func testHuaweiManufacturerCompanyIDIsStrongFingerprint() {
        let fingerprint = HuaweiAdvertisementClassifier.classify(
            name: nil,
            advertisementData: [CBAdvertisementDataManufacturerDataKey: Data([0x7D, 0x02, 0x01, 0x02])]
        )
        XCTAssertGreaterThanOrEqual(fingerprint.score, 5)
        XCTAssertTrue(fingerprint.reasons.contains { $0.contains("0x027D") })
    }

    func testHuaweiAssignedServiceIsFingerprint() {
        let fingerprint = HuaweiAdvertisementClassifier.classify(
            name: nil,
            advertisementData: [CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: "FE35")]]
        )
        XCTAssertGreaterThanOrEqual(fingerprint.score, 2)
        XCTAssertTrue(fingerprint.reasons.contains { $0.contains("FE35") })
    }

    func testHuaweiFingerprintSortsBeforeStrongerGenericDevice() {
        var registry = DiscoveredPeripheralRegistry()
        registry.ingest(id: UUID(), name: "Speaker", rssi: -20, advertisementSummary: "", fingerprint: noFingerprint, seenAt: Date())
        registry.ingest(
            id: UUID(),
            name: nil,
            rssi: -90,
            advertisementSummary: "",
            fingerprint: HuaweiFingerprint(score: 6, reasons: ["Huawei company ID 0x027D"]),
            seenAt: Date()
        )
        XCTAssertEqual(registry.sorted.first?.fingerprint.score, 6)
    }

    func testRSSISortsDescendingAtSamePriority() {
        var registry = DiscoveredPeripheralRegistry()
        registry.ingest(id: UUID(), name: "Device A", rssi: -80, advertisementSummary: "", fingerprint: noFingerprint, seenAt: Date())
        registry.ingest(id: UUID(), name: "Device B", rssi: -30, advertisementSummary: "", fingerprint: noFingerprint, seenAt: Date())
        XCTAssertEqual(registry.sorted.first?.rssi, -30)
    }

    func testKnownHuaweiServicesAreHighlightedCaseInsensitively() {
        XCTAssertTrue(BluetoothUUIDFormatter.isHighlighted("fe35"))
        XCTAssertTrue(BluetoothUUIDFormatter.isHighlighted("0xFD9C"))
        XCTAssertFalse(BluetoothUUIDFormatter.isHighlighted("180F"))
    }

    func testAdvertisementSummaryHandlesUnknownValues() {
        let summary = BluetoothAdvertisementFormatter.summary(["custom": NSObject(), "number": 7])
        XCTAssertTrue(summary.contains("custom="))
        XCTAssertTrue(summary.contains("number=7"))
    }

    func testBoundedLogDropsOldestEntries() async {
        let store = BluetoothLogStore(capacity: 2)
        let peripheral = UUID()
        await store.append(BluetoothLogEntry(id: UUID(), peripheralID: peripheral, serviceUUID: "1", characteristicUUID: "A", payload: Data([1])))
        let second = BluetoothLogEntry(id: UUID(), peripheralID: peripheral, serviceUUID: "2", characteristicUUID: "B", payload: Data([2]))
        let third = BluetoothLogEntry(id: UUID(), peripheralID: peripheral, serviceUUID: "3", characteristicUUID: "C", payload: Data([3]))
        await store.append(second)
        await store.append(third)
        let entries = await store.snapshot()
        XCTAssertEqual(entries.map(\.id), [second.id, third.id])
    }
}
