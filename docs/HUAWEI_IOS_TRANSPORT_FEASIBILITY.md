# Huawei Watch GT2 transport feasibility on iOS

Status: Gate 0 in progress  
Last verified: 2026-07-17  
Current verdict: `UNKNOWN_NEEDS_MORE_EVIDENCE`

## Question

Can an ordinary stock-iOS application open the transport channel used by Huawei Watch GT2 for Huawei protocol packets?

This document deliberately separates three different mechanisms that are easy to conflate:

1. GATT over Bluetooth Low Energy;
2. GATT/ATT available through Core Bluetooth when the controller also supports BR/EDR;
3. a generic serial RFCOMM/SPP socket such as Android `BluetoothSocket`.

Evidence for one mechanism is not evidence for the others.

## Gadgetbridge transport evidence

The current Gadgetbridge project is hosted on Codeberg. F-Droid lists release `0.92.2` added on 2026-07-13, identifies the license as AGPL-3.0-only, and pins version code 251 to source commit `a221d9ab2c0a823bddc6edd18bde8a8f317f75be`.

Codeberg source pages were not directly retrievable by the automated environment. The exact current commit was resolved through F-Droid build metadata, while the transport class relationship was checked against the official archived `Freeyourgadget/Gadgetbridge` GitHub mirror and pinned by file blob SHA in `GADGETBRIDGE_SOURCE_MAP.md`.

The checked source shows:

- `HuaweiWatchGT2Coordinator` extends `HuaweiBRCoordinator`;
- `HuaweiBRCoordinator` extends the Bluetooth Classic coordinator and selects `HuaweiBRSupport`;
- `HuaweiBRSupport` extends `AbstractBTBRDeviceSupport`;
- `HuaweiBRSupport` registers Huawei SDP UUID `82FF3820-8411-400C-B85A-55BDB32CF060` and sets a 1032-byte buffer;
- `AbstractBTBRDeviceSupport` describes its channel as a serial protocol such as RFCOMM Bluetooth or a TCP socket, implemented through the classic I/O thread.

This is strong evidence that Gadgetbridge does not use the `FE86 / FE01 / FE02` BLE path as the primary GT2 packet transport.

## Apple API evidence

### Core Bluetooth

Apple provides Core Bluetooth APIs for GATT communication, including devices whose controller transport may be Bluetooth Classic. Apple also provides:

- `CBConnectPeripheralOptionRequiresANCS`;
- `CBConnectPeripheralOptionEnableTransportBridgingKey`;
- `CBPeripheral.ancsAuthorized`;
- GATT service and characteristic discovery;
- L2CAP CoC APIs when a peripheral publishes an applicable PSM.

Apple documents transport bridging as asking the system to bring up existing non-GATT Classic profiles when a BLE GATT connection exists. The option does not document or return a generic RFCOMM socket to the application.

The Gate 0 probe therefore records the result of transport bridging but never treats successful connection as proof that Huawei RFCOMM packet I/O is available.

### ExternalAccessory

`EAAccessoryManager.shared().connectedAccessories` is inspected read-only. An `EASession` is not opened unless a real accessory appears and exposes a protocol string the application actually understands.

The project does not add a guessed `UISupportedExternalAccessoryProtocols` value. A Bluetooth device visible in Settings is not automatically an ExternalAccessory device.

### ANCS

The probe records `CBPeripheral.ancsAuthorized` and offers a connection attempt using `CBConnectPeripheralOptionRequiresANCS`.

ANCS authorization can prove that the paired watch is allowed to consume iPhone Notification Center data. It does not prove that the Huawei proprietary packet channel is available to the application.

## Implemented Gate 0 checks

The Bluetooth tab now provides:

- unfiltered BLE scan;
- scan filtered to `FE86`;
- scan using `82FF3820-8411-400C-B85A-55BDB32CF060` only as a GATT service filter;
- storage and retrieval of the selected CoreBluetooth identifier;
- read-only connection;
- connection with ANCS required and transport bridging requested;
- service and characteristic metadata discovery;
- ANCS authorization observation;
- ExternalAccessory inventory;
- redacted Markdown and JSON export.

The Gate 0 controller performs no characteristic reads or writes, no notification subscriptions, no L2CAP PSM brute force, no `EASession`, no Huawei authentication, and no destructive command.

## Physical evidence required

Run all three scan modes on the target iPhone and Huawei Watch GT2, then return both exports.

Record:

- exact iPhone and iOS version;
- Xcode/SDK metadata from the report;
- whether Huawei Health was running or stopped;
- whether either GT2 system Bluetooth entry changed state;
- whether `FE86` produced the watch;
- whether the 128-bit Huawei SDP UUID produced the watch as GATT;
- all discovered services and characteristics;
- ANCS authorization before and after the ANCS-required connection;
- every ExternalAccessory record and protocol string.

Do not unpair, reset, remove a bond, or uninstall Huawei Health for Gate 0.

## Verdict rules

- `FEASIBLE_BLE_GATT`: a usable GT2 GATT byte channel is physically demonstrated.
- `FEASIBLE_BR_EDR_GATT`: a usable Core Bluetooth GATT channel over BR/EDR is physically demonstrated.
- `FEASIBLE_EXTERNAL_ACCESSORY`: GT2 appears through ExternalAccessory with a usable declared protocol and session path.
- `BLOCKED_PRIVATE_RFCOMM`: evidence shows the required channel is private RFCOMM/SPP and no public iOS application API exposes it.
- `UNKNOWN_NEEDS_MORE_EVIDENCE`: current state before the physical matrix is complete.

## Current conclusion

The source evidence makes private RFCOMM the principal risk. The iOS diagnostic code can disprove some paths, but simulator CI cannot settle the transport question. Protocol, authentication, crypto, music, and notification packet work remain blocked until this Gate produces physical evidence and the license mode is selected.
