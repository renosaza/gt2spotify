# GT2Spotify

GT2Spotify is an experimental iOS companion app intended to receive music-control commands from a Huawei Watch GT2 and forward them to Spotify on an iPhone.

This branch implements **Phase 0 and Phase 1 only**: the iOS bootstrap and a standalone Spotify Web API control path. It does **not** scan, pair, bond, reset, or write to a Huawei watch.

## Current scope

- SwiftUI app, iOS 16+
- Spotify Authorization Code with PKCE; no client secret
- Keychain storage for OAuth state, verifier, access token, and refresh token
- refresh-token handling, including Spotify's six-month refresh-token lifetime
- Spotify Web API playback state, devices, play, pause, next, previous, and supported-device volume
- decoding of Spotify's `supports_volume` capability and device-targeted volume commands
- native `MPVolumeView` fallback when the active iPhone client does not accept Spotify Web API volume commands
- one refresh and one retry after HTTP 401
- explicit 403, 404, 429, network, and decoding diagnostics
- URLProtocol-backed unit tests
- unsigned GitHub Actions simulator build and tests
- HTTPS GitHub Pages callback that forwards to `gt2spotify://oauth/callback`

## Safety boundary

Huawei BLE, authentication, bonding, packet writes, unpairing, and watch reset are intentionally absent. Hardware behavior remains unverified until tested on a physical iPhone and Huawei Watch GT2.

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
7. Enable GitHub Pages for the repository and publish the `/docs` directory. Until the PR is merged, Pages may be pointed temporarily at the feature branch; after merge, use `main` and `/docs`.

More detail: [docs/spotify-dashboard.md](docs/spotify-dashboard.md).

## Run on a physical iPhone with Personal Team

1. Open `GT2Spotify.xcodeproj` in Xcode.
2. Select the `GT2Spotify` project, then the `GT2Spotify` target.
3. Open **Signing & Capabilities**.
4. Enable **Automatically manage signing**.
5. Choose your Apple Account's **Personal Team**.
6. Change the bundle identifier if `com.renosaza.gt2spotify` is unavailable for your account.
7. Connect the iPhone by cable, trust the Mac, and select it as the run destination.
8. On the iPhone, enable **Developer Mode** when iOS requests it, then restart/confirm as instructed by iOS.
9. Build and run from Xcode.
10. Tap **Connect Spotify**, approve the two scopes, and return through the GitHub Pages callback.
11. Start playback in Spotify and make the iPhone or another Spotify Connect device active.
12. Test refresh, play, pause, previous, and next.
13. When the active Connect device reports `supports_volume = true`, test the Spotify Web API volume buttons and slider.
14. When the active iPhone reports `supports_volume = false`, use the native iOS system volume slider shown by the app.

A Personal Team provisioning profile expires after seven days, so periodic rebuild/reinstall is expected.

## Local validation

On macOS:

```bash
xcodebuild \
  -project GT2Spotify.xcodeproj \
  -scheme GT2Spotify \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

Verify the effective local configuration before running OAuth:

```bash
xcodebuild \
  -project GT2Spotify.xcodeproj \
  -scheme GT2Spotify \
  -destination 'generic/platform=iOS' \
  -showBuildSettings |
grep -E 'SPOTIFY_CLIENT_ID|SPOTIFY_REDIRECT_URI|APP_URL_SCHEME'
```

`SPOTIFY_REDIRECT_URI` must expand to the complete HTTPS URL, not just `https:`.

The Spotify Client ID is not required for compilation or mocked unit tests. Without it, the app shows a configuration error instead of starting authorization.

## Repository layout

- `GT2Spotify/App` — composition root and SwiftUI entry point
- `GT2Spotify/Features/Dashboard` — Phase 1 test UI
- `GT2Spotify/Spotify` — PKCE, token lifecycle, Web API, player controller
- `GT2Spotify/Support` — configuration, Keychain, logging, redaction
- `GT2Spotify/Bridge` — hardware-independent music command domain
- `GT2SpotifyTests` — PKCE and URLProtocol-backed API tests
- `docs` — architecture, source attribution, test matrix, OAuth callback

## Known limitations

- The GitHub Pages → custom-scheme callback is an architecture choice, not an official Spotify mobile sample. It must be proven on the target iPhone/Safari combination.
- Player-control endpoints require Spotify Premium and can return 404 when there is no active device.
- Spotify clients may report `supports_volume = false`. In that case the app must use the native iOS volume UI rather than sending a Web API volume command.
- The native iOS system volume control works only on a physical device, not in the Simulator.
- No result in this repository proves Huawei Watch GT2 compatibility yet.
- Force-closing an eventual BLE-enabled app can affect background restoration; this is outside Phase 1.

## License and attribution

Original project code is MIT licensed. See [docs/source-attribution.md](docs/source-attribution.md) before implementing Huawei protocol phases.
