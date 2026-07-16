# Spotify Dashboard configuration

## Create the app

Create a Spotify app while signed in with the Premium account that will own and test GT2Spotify.

Recommended values:

- **App name:** `GT2Spotify`
- **App description:** `Personal iOS companion for controlling Spotify from a Huawei Watch GT2`
- **Website:** `https://github.com/renosaza/gt2spotify`
- **Redirect URI:** `https://renosaza.github.io/gt2spotify/oauth/callback.html`
- **API/SDK:** select **Web API**

The redirect URI must match exactly, including scheme, host, path, case, and the absence of a trailing slash. Do not register `localhost`; Phase 1 uses the HTTPS GitHub Pages bridge.

The app requests only:

```text
user-read-playback-state user-modify-playback-state
```

Copy the public **Client ID** after creating the app. A client secret must never be placed in the iOS app, `Config.xcconfig`, CI, or this repository.

If a Spotify account other than the app owner will test the Development Mode app, add it in the Dashboard's user-management section. New Development Mode apps currently allow up to five users, and the owner must keep an active Premium subscription.

## Local Xcode configuration

```bash
cp Config.example.xcconfig Config.xcconfig
```

Then edit:

```xcconfig
SPOTIFY_CLIENT_ID = your_public_client_id
APP_URL_SCHEME = gt2spotify
```

Leave these values unchanged unless the app code and Dashboard are updated together:

```xcconfig
SPOTIFY_REDIRECT_URI = https://renosaza.github.io/gt2spotify/oauth/callback.html
APP_URL_SCHEME = gt2spotify
```

`Config.xcconfig` is ignored by Git.

## GitHub Pages

The callback page is `docs/oauth/callback.html`.

In repository settings:

1. Open **Settings → Pages**.
2. Under **Build and deployment**, choose **Deploy from a branch**.
3. Select `feat/bootstrap` and `/docs` while validating this draft PR.
4. Save and wait until the public callback URL loads over HTTPS.
5. Open `https://renosaza.github.io/gt2spotify/oauth/callback.html` without query parameters. It should show a harmless missing-response message and must not load analytics or external scripts.
6. After merging the PR, switch the Pages source to `main` and `/docs`.

The Pages-to-custom-scheme hop is an implementation choice, not an official Spotify mobile sample. It remains unverified until the complete browser flow succeeds on the target physical iPhone.

## Development Mode limits

Under Spotify's February 2026 Development Mode rules, the app owner must have Premium, a developer can create one new Client ID, and a new app can have up to five users. Re-check the Dashboard if Spotify changes these limits.
