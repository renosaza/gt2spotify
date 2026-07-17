# Gadgetbridge licensing boundary

Status: unresolved by design  
Verified: 2026-07-17

## Current licenses

- `gt2spotify`: MIT
- current Gadgetbridge release metadata: AGPL-3.0-only

The Gate 0 branch keeps the repository under MIT because it contains original platform-diagnostic code and does not port Gadgetbridge protocol implementation.

## Prohibited work until a mode is selected

Do not copy, translate, structurally port, or derive implementations of:

- `HuaweiPacket`;
- `HuaweiTLV`;
- `HuaweiCrypto`;
- authentication/session requests;
- `MusicControl`;
- notification packet encoders;
- Huawei packet fragmentation or checksum code.

Do not describe implementation work as clean-room when the implementer has used the Gadgetbridge implementation as a coding reference.

## Available modes

### Mode A — AGPL derivative

Requires explicit user approval before changing the repository license.

If selected:

- replace or update the repository license to a compatible AGPL form;
- preserve Gadgetbridge copyright notices and attribution;
- record the exact source host, commit, paths, and transferred portions;
- publish the complete corresponding source;
- mark derived files clearly.

### Mode B — clean-room

Requires strict separation:

- one stage produces a protocol specification and test vectors without implementation code transfer;
- an independent implementation stage writes Swift from that specification;
- no copy/paste, line-by-line translation, or preservation of source structure;
- people who studied the source implementation must not later claim their implementation is clean-room without a documented separation process.

## Current decision

No mode has been selected. No repository license change has been made.

Allowed work while unresolved:

- Apple platform API research;
- CoreBluetooth and ExternalAccessory diagnostics;
- redacted report export;
- original test infrastructure;
- documentation of factual transport findings.

Blocked work while unresolved:

- Huawei protocol implementation;
- Huawei crypto/authentication implementation;
- music or notification packet port;
- Gadgetbridge-derived fixtures or test vectors.

## Next decision point

Only after Gate 0 proves a usable iOS transport should the user choose between AGPL derivative and clean-room mode. If Gate 0 returns `BLOCKED_PRIVATE_RFCOMM`, there is no reason to relicense this repository for a direct iOS port.
