# Gadgetbridge source map for Huawei Watch GT2

Verified: 2026-07-17

## Canonical project location

- Current project host: `https://codeberg.org/Freeyourgadget/Gadgetbridge`
- Current release observed through F-Droid: `0.92.2`, added 2026-07-13
- License reported by F-Droid: `AGPL-3.0-only`

The automated environment could not retrieve Codeberg source pages during this run. An exact full Codeberg commit SHA is therefore still pending. Do not silently substitute the archived GitHub mirror as the current canonical repository.

## Architecture cross-check source

Official archived mirror used for class and transport verification:

`https://github.com/Freeyourgadget/Gadgetbridge`

The following file blobs were fetched directly from that mirror:

| File | Blob SHA | Finding |
|---|---|---|
| `app/src/main/java/nodomain/freeyourgadget/gadgetbridge/devices/huawei/huaweiwatchgt2/HuaweiWatchGT2Coordinator.java` | `b55b9340846100055c67d3fc00752cab8f1481a6` | `HuaweiWatchGT2Coordinator` extends `HuaweiBRCoordinator`. |
| `app/src/main/java/nodomain/freeyourgadget/gadgetbridge/devices/huawei/HuaweiBRCoordinator.java` | `447e9a1b2a30a13850c61bd51d581ad4d4a6ddcf` | Extends the Bluetooth Classic coordinator and returns `HuaweiBRSupport`. |
| `app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/devices/huawei/HuaweiBRSupport.java` | `685eb6163aa2506c22954e749a8edbeecead7093` | Extends `AbstractBTBRDeviceSupport`, registers the Huawei SDP UUID, and sets buffer size 1032. |
| `app/src/main/java/nodomain/freeyourgadget/gadgetbridge/service/btbr/AbstractBTBRDeviceSupport.java` | `479a484dfd4ac197de8b126dbae0be6af4056d1a` | Describes a serial transport such as RFCOMM Bluetooth or TCP socket through the classic I/O thread. |

## Transport identifiers

Huawei BR SDP/service UUID observed in the checked source:

`82FF3820-8411-400C-B85A-55BDB32CF060`

Huawei BLE identifiers exist elsewhere in Gadgetbridge:

- service: `FE86`
- write characteristic: `FE01`
- read characteristic: `FE02`

These BLE identifiers must not be assumed to provide the same GT2 transport as `HuaweiBRSupport`.

## Files still required before any protocol implementation

The following files must be rechecked against an exact current Codeberg commit before direct implementation work:

- `devices/huawei/HuaweiConstants.java`
- `devices/huawei/HuaweiPacket.java`
- `devices/huawei/HuaweiTLV.java`
- `devices/huawei/HuaweiCrypto.java`
- `devices/huawei/HuaweiMusicUtils.java`
- `devices/huawei/packets/MusicControl.java`
- `devices/huawei/packets/Notifications.java`
- `service/devices/huawei/HuaweiLESupport.java`
- `service/devices/huawei/HuaweiSupportProvider.java`
- `service/devices/huawei/HuaweiMusicManager.java`
- `service/devices/huawei/requests/`
- `service/btclassic/BtClassicIoThread.java`

## Use status

No Gadgetbridge implementation code has been copied, translated, or ported in the Gate 0 branch. The checked files were used only to establish the transport architecture and licensing boundary.

Before a later protocol PR:

1. resolve and record an exact Codeberg commit SHA or signed release tag;
2. select AGPL derivative or clean-room mode;
3. record every source file actually studied or transferred;
4. preserve required copyright and license notices if derivative mode is selected.
