# Phase 1 test matrix

## Automated

| Scenario | Expected |
|---|---|
| RFC 7636 verifier | exact S256 challenge |
| Authorization URL | client ID, exact redirect, state, scopes, S256 challenge |
| Playback state JSON | decoded track, artist, state, device, volume, and `supports_volume` |
| Device list JSON | each device exposes remote-volume capability |
| HTTP 204 playback | nil playback state |
| HTTP 401 | one refresh request and one player retry only |
| Refresh response without refresh token | retain previous refresh token |
| HTTP 403 | explicit forbidden error |
| HTTP 404 | explicit no-active-device error |
| HTTP 429 | explicit rate-limit error with `Retry-After` |
| Invalid JSON | explicit decoding error |
| Volume outside range | clamp to 0...100 |
| Supported active volume device | command includes the active `device_id` |
| Unsupported active volume device | reject Web API volume command before sending it |

## Manual on physical iPhone

| Scenario | Expected |
|---|---|
| Missing Client ID | clear configuration error; no browser session |
| Effective redirect build setting | complete HTTPS URI, not truncated to `https:` |
| First Spotify login | scopes shown; callback returns to app |
| State mismatch | authorization rejected; no token saved |
| Relaunch after login | token remains available from Keychain |
| Access token expiry | transparent refresh and command execution |
| Refresh token expiry/revocation | stored token cleared; reauthorization required |
| Spotify playing | play/pause/next/previous work |
| Connect device with `supports_volume = true` | relative ±5% and exact Web API volume work |
| iPhone with `supports_volume = false` | Web API slider is replaced by native iOS system volume control |
| Native system volume control | changing slider changes physical-device output volume |
| No active device | visible 404 diagnostic and Open Spotify action |
| Non-Premium/blocked command | visible 403 diagnostic |
| Rate limit | visible 429 diagnostic; no retry loop |
| Pages bridge blocked from auto-open | manual Open GT2Spotify button works |

## Not tested in Phase 1

- Huawei Watch discovery or coexistence with Huawei Health
- FE01/FE02 characteristics
- Huawei authentication or bonding
- music service `0x25`
- locked-screen BLE wake or state restoration
