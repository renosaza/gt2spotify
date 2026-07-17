# Phase 2: safe BLE discovery and raw logger

## Architecture

`BluetoothCentralController` owns `CBCentralManager`, scanning, connect/disconnect, service and characteristic discovery, and notification subscriptions. UI receives value snapshots rather than exposing CoreBluetooth objects.

`DiscoveredPeripheralRegistry` deduplicates scan events by peripheral UUID and sorts Huawei/watch-like names first, then by strongest RSSI.

`BluetoothLogStore` is an actor with a bounded 2,000-entry buffer. Export is generated only after an explicit user action.

The Bluetooth dashboard is a separate application tab. Simulator builds remain supported, although scanning requires a physical iPhone.

## Privacy

The app requests Bluetooth access only for nearby-device discovery and inspection. It does not log Spotify access tokens, refresh tokens, OAuth codes, client secrets, Keychain values, Apple credentials, or Huawei Health credentials.

Raw BLE logs may contain peripheral UUIDs, service UUIDs, characteristic UUIDs, timestamps, payload bytes, RSSI, and advertisement metadata. Users should review exported logs before sharing them.

No Bluetooth background modes or state restoration are enabled.

## Safety boundary

Phase 2 performs only:

- BLE scan start and stop;
- connect and disconnect;
- service and characteristic discovery;
- subscription to characteristics advertising `notify` or `indicate`;
- passive receipt and logging of notification bytes.

It contains no characteristic writes, Huawei authentication, handshake, bonding, pairing implementation, unpairing, bond removal, factory reset, packet replay, ownership takeover, service `0x25` handling, background reconnect, or Spotify commands derived from BLE packets.

The watch should remain associated with Huawei Health. A watch already connected to Huawei Health may not advertise or may reject a second connection; that is reported as a limitation rather than treated automatically as an application bug.

## Automated validation

Unit coverage includes:

- duplicate scan-event merging;
- RSSI and `lastSeen` updates;
- Huawei/watch name priority;
- RSSI ordering within the same priority;
- uppercase spaced hex and empty payload formatting;
- case-insensitive FE01/FE02 recognition;
- unknown advertisement values;
- bounded-log eviction of oldest entries.

## Manual Gate 2

Test only on a physical iPhone:

- [ ] Bluetooth permission is requested with the expected explanation.
- [ ] All CoreBluetooth states render correctly.
- [ ] Scan starts and stops.
- [ ] Nearby devices appear without UUID duplicates.
- [ ] Huawei Watch GT2 appears, or the UI gives honest coexistence diagnostics.
- [ ] Connect and disconnect do not disrupt Huawei Health.
- [ ] Services and characteristics appear.
- [ ] FE01 and FE02 are highlighted when present.
- [ ] Only notify/indicate characteristics are subscribed.
- [ ] Incoming notifications appear in the raw log.
- [ ] Clear and text-file export work.
- [ ] After closing GT2Spotify, normal Huawei Health/watch operation continues.
- [ ] No writes, bonding, unpairing, reset, or Huawei authentication occurred.

Passing CI does not prove Huawei Watch GT2 compatibility. Phase 3 must not start until this gate is confirmed manually.
