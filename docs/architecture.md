# Architecture

## Phase 0–1 boundary

The current implementation deliberately proves Spotify control before any Huawei BLE work.

```text
SwiftUI Dashboard
      │
      ├── SpotifyAuthorizationController
      │      ├── ASWebAuthenticationSession
      │      ├── SpotifyOAuthClient (PKCE token exchange/refresh)
      │      └── SpotifyTokenStore → Keychain
      │
      └── SpotifyPlayerController
             └── SpotifyAPIClient
                    ├── SpotifyTokenManager
                    └── Spotify Web API
```

## Composition

`AppContainer` creates concrete dependencies once:

- `SystemKeychainStore`
- `SpotifyTokenStore`
- `SpotifyOAuthClient`
- `SpotifyTokenManager`
- `SpotifyAPIClient`
- `SpotifyPlayerController`
- `SpotifyAuthorizationController`
- `DashboardViewModel`

The token store and network clients are actors. UI state is isolated to `MainActor`.

## OAuth flow

1. Generate a cryptographically random PKCE verifier and state.
2. Derive the S256 challenge.
3. Persist pending verifier/state in Keychain before leaving the app.
4. Start Spotify authorization with the HTTPS redirect URI.
5. GitHub Pages forwards the returned `code`, `state`, or `error` to `gt2spotify://oauth/callback` without analytics or server-side storage.
6. Validate callback state exactly.
7. Exchange the code using the original HTTPS redirect URI, Client ID, and verifier.
8. Persist the token set in Keychain and remove pending authorization data.

The callback bridge must be validated on a physical iPhone before Phase 1 is accepted.

## Token lifecycle

- Access tokens are treated as expired 60 seconds early.
- Refresh is performed with `client_id`, never with a client secret.
- A refresh response may omit a new refresh token; the prior one is retained.
- The original refresh-token expiration timestamp is retained across access-token refreshes.
- `invalid_grant` clears the stored token and requires authorization again.
- API requests perform at most one forced refresh and one retry after HTTP 401.

## Player errors

- 403 → forbidden/Premium/permission/playback restriction diagnostic
- 404 → no active Spotify device
- 429 → rate-limited error carrying parsed `Retry-After`
- 204 from playback state → no current playback snapshot
- malformed or incomplete JSON → decoding diagnostic

## Future boundary

Huawei BLE transport, Link Protocol v2, authentication, bonding, music service `0x25`, and background restoration are separate later phases. They must depend on the hardware-independent `MusicCommand` model and must not weaken Spotify token storage or retry bounds.
