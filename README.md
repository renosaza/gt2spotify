# GT2Spotify

GT2Spotify is an experimental iOS companion app intended to receive music-control commands from a Huawei Watch GT2 and forward them to Spotify on an iPhone.

The current build contains the Spotify control path and a read-only Bluetooth inspection phase. It does not implement the Huawei protocol handshake and does not send BLE writes.

## Current scope

- SwiftUI app, iOS 16+
- Spotify Authorization Code with PKCE; no client secret
- Keychain storage for OAuth state, verifier, access token, and refresh token
- Spotify Web API playback state, devices, play, pause, next, previous, and supported-device volume
- native `MPVolumeView` fallback when the active iPhone client does not accept Spotify Web API volume commands
- Bluetooth permission and `CBCentralManager` state handling
- unrestricted foreground BLE scan with UUID deduplication, RSSI, last-seen time, and advertisement diagnostics
- readable temporary names for unnamed peripherals, such as `Unknown • ABCDEF`
- lookup of system-connected BLE candidates exposing service `FE01` or `FE02`
- explicit local storage of the selected watch's CoreBluetooth UUID for later retrieval
- connect/disconnect, service and characteristic discovery
- notification subscription only for characteristics advertising `notify` or `indicate`
- bounded raw notification log with clear and text export
- simulator build and unit tests in GitHub Actions

## Safety boundary

Bluetooth support is limited to discovery, connected-peripheral lookup, local identifier storage, connect/disconnect, service inspection, notify/indicate subscription, and raw receive logging.

The app performs no characteristic writes, Huawei authentication, handshake, pairing or bonding implementation, unpairing, reset, replay, ownership takeover, background reconnect, or BLE-driven Spotify control.

## Requirements

- a Mac with a current Xcode release capable of building Swift 6 projects
- iOS 16 or later on a physical iPhone
- a normal Apple Account added to Xcode; a paid developer membership is not required for personal device testing
- a Spotify Premium account that owns the Spotify Developer app
- Spotify installed and an active Spotify Connect playback device for player commands

## Configure Spotify

1. Create an app in the Spotify Developer Dashboard.
2. Add this exact redirect URI:

   `https://renosaza.github.io/gt2spotify/oauth/callback.html`

3. Use only these scopes:

   - `user-read-playback-state`
   - `user-modify-playback-state`

4. Copy `Config.example.xcconfig` to `Config.xcconfig`.
5. Put the public Client ID in `SPOTIFY_CLIENT_ID`. Do not add a client secret.
6. Keep the xcconfig-safe redirect expression from the example file. Raw `https://...` values are truncated because `//` starts an xcconfig comment.
7. Enable GitHub Pages for the repository and publish the `/docs` directory.

More detail: [docs/spotify-dashboard.md](docs/spotify-dashboard.md).

## Run on a physical iPhone with Personal Team

1. Open `GT2Spotify.xcodeproj` in Xcode.
2. Select the `GT2Spotify` project, then the `GT2Spotify` target.
3. Open **Signing & Capabilities**.
4. Enable **Automatically manage signing**.
5. Choose your Apple Account's **Personal Team**.
6. Change the bundle identifier if `com.renosaza.gt2spotify` is unavailable for your account.
7. Connect the iPhone by cable, trust the Mac, and select it as the run destination.
8. On the iPhone, enable **Developer Mode** when iOS requests it.
9. Build and run with `⌘R`.

A Personal Team provisioning profile expires after seven days, so periodic rebuild/reinstall is expected.

## Bluetooth identification workflow

1. Keep Huawei Health and the normal watch connection intact.
2. Open the **Bluetooth** tab and grant Bluetooth permission.
3. Tap **Refresh connected devices**. The app asks CoreBluetooth for system-connected peripherals exposing `FE01` or `FE02`.
4. If a candidate appears, connect and inspect its services.
5. If no candidate appears, start a scan. Unnamed devices are shown with a stable short suffix instead of identical `Unknown` labels.
6. Once the watch is identified, tap **Remember as watch**. The app stores only the iOS CoreBluetooth UUID in `UserDefaults`.
7. On later launches, the **Remembered watch** section attempts `retrievePeripherals(withIdentifiers:)` before requiring another scan.

CoreBluetooth does not expose the physical BLE MAC address and cannot enumerate every paired Bluetooth device. The MAC shown by Huawei Health or the watch cannot be directly matched to the UUID shown by this app.

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

Verify the effective local Spotify configuration before OAuth:

```bash
xcodebuild \
  -project GT2Spotify.xcodeproj \
  -scheme GT2Spotify \
  -destination 'generic/platform=iOS' \
  -showBuildSettings |
grep -E 'SPOTIFY_CLIENT_ID|SPOTIFY_REDIRECT_URI|APP_URL_SCHEME'
```

## Repository layout

- `GT2Spotify/App` — composition root and SwiftUI entry point
- `GT2Spotify/Features/Dashboard` — Spotify test UI and currently compiled Bluetooth UI
- `GT2Spotify/Features/Bluetooth` — readable mirror of the Bluetooth UI
- `GT2Spotify/Spotify` — PKCE, token lifecycle, Web API, player controller
- `GT2Spotify/Bluetooth` — readable Bluetooth model/controller mirrors
- `GT2Spotify/Bridge` — music-command domain and currently compiled Bluetooth implementation
- `GT2Spotify/Support` — configuration, Keychain, logging, redaction
- `GT2SpotifyTests` — PKCE, API, and Bluetooth pure-logic tests
- `docs` — architecture, source attribution, test matrix, OAuth callback

## Known limitations

- CoreBluetooth scanning and connected-device retrieval require a physical iPhone.
- `retrieveConnectedPeripherals(withServices:)` only returns connected peripherals matching the supplied service UUIDs; it is not a generic list of all paired devices.
- A watch already managed by Huawei Health may not advertise a name or accept a second connection.
- Spotify clients may report `supports_volume = false`; the app then uses native iOS system volume instead of a Spotify Web API volume command.
- Passing CI does not prove Huawei Watch GT2 protocol compatibility.

## License and attribution

Original project code is MIT licensed. See [docs/source-attribution.md](docs/source-attribution.md) before implementing Huawei protocol phases.
