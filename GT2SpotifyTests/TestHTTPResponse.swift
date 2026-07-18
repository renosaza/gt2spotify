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
        let id = UUID()
        let first = Date(timeIntervalSince1970: 1)
        let second = Date(timeIntervalSince1970: 2)
        var registry = DiscoveredPeripheralRegistry()
        registry.ingest(id: id, name: "HUAWEI WATCH GT 2", rssi: -80, advertisementSummary: "first", seenAt: first)
        registry.ingest(id: id, name: nil, rssi: -45, advertisementSummary: "second", seenAt: second)
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
            lastSeen: Date()
        )
        XCTAssertEqual(peripheral.shortIdentifier, "ABCDEF")
        XCTAssertEqual(peripheral.displayName, "Unknown • ABCDEF")
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

    func testConnectedCandidateAggregatesMatchedServices() {
        let id = UUID()
        var registry = ConnectedPeripheralCandidateRegistry()
        registry.ingest(id: id, name: nil, serviceUUID: "FE02", isRemembered: false)
        registry.ingest(id: id, name: "HUAWEI WATCH GT 2", serviceUUID: "FE01", isRemembered: false)
        registry.ingest(id: id, name: nil, serviceUUID: "FE01", isRemembered: false)

        XCTAssertEqual(registry.values.count, 1)
        XCTAssertEqual(registry.values[id]?.name, "HUAWEI WATCH GT 2")
        XCTAssertEqual(registry.values[id]?.matchedServiceUUIDs, ["FE01", "FE02"])
    }

    func testRememberedConnectedCandidateSortsFirst() {
        let rememberedID = UUID()
        var registry = ConnectedPeripheralCandidateRegistry()
        registry.ingest(id: UUID(), name: "Huawei Watch", serviceUUID: "FE01", isRemembered: false)
        registry.ingest(id: rememberedID, name: nil, serviceUUID: "FE02", isRemembered: true)
        XCTAssertEqual(registry.sorted.first?.id, rememberedID)
    }

    func testKnownConnectedProbeServicesRemainReadOnlyIdentifiers() {
        XCTAssertEqual(BluetoothKnownServices.connectedProbeUUIDStrings, ["FE01", "FE02"])
        XCTAssertEqual(BluetoothKnownServices.connectedProbeUUIDs.map(\.uuidString), ["FE01", "FE02"])
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

final class TransportFeasibilityTests: XCTestCase {
    func testGateZeroScanFiltersAreExact() {
        XCTAssertNil(TransportScanMode.all.serviceStrings)
        XCTAssertEqual(TransportScanMode.fe86.serviceStrings, ["FE86"])
        XCTAssertEqual(
            TransportScanMode.huaweiSDP.serviceStrings,
            ["82FF3820-8411-400C-B85A-55BDB32CF060"]
        )
    }

    func testReportDefaultsToUnknownWithoutPhysicalEvidence() throws {
        let report = fixtureReport()
        let json = try TransportReportFormatter.json(report)
        XCTAssertTrue(json.contains("UNKNOWN_NEEDS_MORE_EVIDENCE"))
        XCTAssertFalse(json.contains("access_token"))
        XCTAssertFalse(json.contains("refresh_token"))
        XCTAssertFalse(json.contains("notification body"))
    }

    func testMarkdownStatesPhysicalEvidenceLimitation() {
        let markdown = TransportReportFormatter.markdown(fixtureReport())
        XCTAssertTrue(markdown.contains("Simulator CI is not Bluetooth evidence"))
        XCTAssertTrue(markdown.contains("82FF3820-8411-400C-B85A-55BDB32CF060"))
        XCTAssertTrue(markdown.contains("No Spotify token"))
    }

    private func fixtureReport() -> TransportReport {
        TransportReport(
            generatedAt: "2026-07-17T12:00:00Z",
            verdict: .unknownNeedsMoreEvidence,
            iOSVersion: "test",
            model: "test",
            xcodeBuild: "test",
            sdkName: "test",
            bluetoothState: "Powered On",
            bluetoothAuthorization: "Allowed always",
            scanMode: TransportScanMode.huaweiSDP.rawValue,
            rememberedIdentifier: nil,
            connectedIdentifier: nil,
            peripherals: [],
            services: [],
            accessories: [],
            notes: ["82FF3820-8411-400C-B85A-55BDB32CF060 is not proof of RFCOMM"]
        )
    }
}
