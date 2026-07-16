# Spotify Dashboard configuration

## App settings

Create a Spotify app owned by the Premium account used for testing.

Set the redirect URI exactly to:

```text
https://renosaza.github.io/gt2spotify/oauth/callback.html
```

Exact matching matters, including scheme, host, path, case, and trailing slash. Do not register `localhost`; this project does not use a loopback callback in Phase 1.

The app requests only:

```text
user-read-playback-state user-modify-playback-state
```

No client secret belongs in an iOS app or in this repository.

## Local Xcode configuration

```bash
cp Config.example.xcconfig Config.xcconfig
```

Then edit:

```xcconfig
SPOTIFY_CLIENT_ID = your_public_client_id
APP_URL_SCHEME = gt2spotify
```

`Config.xcconfig` is ignored by Git.

## GitHub Pages

The callback page is `docs/oauth/callback.html`.

In repository settings:

1. Open **Settings → Pages**.
2. Select **Deploy from a branch**.
3. Select the branch containing this code and the `/docs` folder.
4. Wait until the public callback URL loads over HTTPS.
5. After merging, switch the Pages source to `main` and `/docs`.

Before testing OAuth, open the callback URL without query parameters. It should render a harmless “Missing OAuth response” status and must not display analytics or external requests.

## Development Mode limits

As of the February 2026 Spotify migration rules, a Development Mode app owner must have Premium, a developer can create one new Client ID, and a new app can have up to five users. Verify the Dashboard again if Spotify changes these limits.
