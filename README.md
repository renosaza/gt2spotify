# GT2Spotify

GT2Spotify is an experimental iOS companion app intended to receive music-control commands from a Huawei Watch GT2 and forward them to Spotify on an iPhone.

The current branch contains the Spotify control path and **Gate 0 transport diagnostics**. It does not implement Huawei authentication, packet encoding, crypto, notification forwarding, or BLE-driven Spotify control.

## Current scope

- SwiftUI, iOS 16+, Swift 6
- Spotify Authorization Code with PKCE; no client secret
- Spotify tokens in Keychain
- Spotify playback state, devices, play, pause, next, previous, and supported-device volume
- public `MPVolumeView` fallback for local iPhone volume
- CoreBluetooth scan modes:
  - all BLE advertisements;
  - Huawei `FE86` as a GATT service filter;
  - Huawei SDP UUID `82FF3820-8411-400C-B85A-55BDB32CF060` only as a GATT service filter
- saved CoreBluetooth identifier retrieval
- read-only connection and GATT service/characteristic metadata discovery
- ANCS authorization observation and an explicit ANCS-required connection probe
- system transport-bridging request recorded only as diagnostic evidence
- read-only ExternalAccessory inventory
- redacted Markdown and JSON transport reports
- simulator build and unit tests in GitHub Actions

## Current transport verdict

`UNKNOWN_NEEDS_MORE_EVIDENCE`

Gadgetbridge routes Huawei Watch GT2 through its Huawei BR support, which uses a serial Bluetooth Classic/RFCOMM-style transport. Core Bluetooth support for Bluetooth Classic GATT does not by itself prove that stock iOS exposes an arbitrary RFCOMM socket to an application.

The verdict requires a physical iPhone and Huawei Watch GT2. Simulator CI is not Bluetooth evidence.

See:

- `docs/HUAWEI_IOS_TRANSPORT_FEASIBILITY.md`
- `docs/GADGETBRIDGE_SOURCE_MAP.md`
- `docs/LICENSING_GADGETBRIDGE.md`

## Safety boundary

Gate 0 performs only:

- scan;
- saved-identifier retrieval;
- connect/disconnect;
- service and characteristic metadata discovery;
- ANCS authorization observation;
- ExternalAccessory inventory;
- redacted export.

Gate 0 performs no characteristic reads or writes, notification subscriptions, L2CAP PSM brute force, `EASession` creation, Huawei authentication, pairing reset, unpairing, bond removal, protocol packet transmission, or background reconnect.

## Configure Spotify

1. Create an app in the Spotify Developer Dashboard.
2. Add this exact redirect URI:

   `https://renosaza.github.io/gt2spotify/oauth/callback.html`

3. Use only these scopes:

   - `user-read-playback-state`
   - `user-modify-playback-state`

4. Copy `Config.example.xcconfig` to `Config.xcconfig`.
5. Put the public Client ID in `SPOTIFY_CLIENT_ID`. Do not add a client secret.
6. Keep the xcconfig-safe redirect expression from the example file.
7. Enable GitHub Pages for the repository and publish `/docs`.

More detail: `docs/spotify-dashboard.md`.

## Run on a physical iPhone

1. Open `GT2Spotify.xcodeproj` in Xcode.
2. Select the `GT2Spotify` target.
3. Open **Signing & Capabilities**.
4. Enable **Automatically manage signing**.
5. Choose your Apple Account's Personal Team.
6. Change the bundle identifier if needed.
7. Connect and trust the iPhone, then select it as the run destination.
8. Enable Developer Mode when iOS requests it.
9. Build and run with `⌘R`.

A Personal Team provisioning profile expires after seven days.

## Gate 0 physical workflow

Keep Huawei Health and the current pairing intact.

1. Open the **Bluetooth** tab.
2. Run **All BLE advertisements**.
3. Identify the likely watch, remember its CoreBluetooth identifier, and try **Connect read-only**.
4. Export Markdown and JSON.
5. Run the `FE86` filtered scan and export again.
6. Run the Huawei SDP UUID-as-GATT scan and export again.
7. Try **Connect + ANCS** on the identified watch.
8. Refresh ExternalAccessory and export the final report.
9. Return the reports and screenshots of the GATT service dump.

Do not reset, unpair, remove a bond, or add guessed ExternalAccessory protocol strings.

## Local validation

```bash
xcodebuild \
  -project GT2Spotify.xcodeproj \
  -scheme GT2Spotify \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

## Repository layout

- `GT2Spotify/App` — composition root
- `GT2Spotify/Features/Dashboard` — Spotify and Gate 0 UI
- `GT2Spotify/Spotify` — Spotify PKCE, token lifecycle, Web API, player controller
- `GT2Spotify/Bridge` — music-command domain and legacy BLE diagnostic support
- `GT2Spotify/Support` — configuration, Keychain, logging, redaction
- `GT2SpotifyTests` — pure logic and report tests
- `docs` — architecture, feasibility, attribution, and OAuth callback

## License and attribution

Original project code remains MIT licensed. Gadgetbridge is AGPL-3.0-only according to current release metadata.

No Gadgetbridge protocol implementation has been ported in Gate 0. A later direct port requires an explicit AGPL derivative or documented clean-room decision first.
