# Source attribution

## Original code

The GT2Spotify code in this repository is licensed under the MIT License.

## Spotify

The Phase 1 implementation follows Spotify's public documentation for:

- Authorization Code with PKCE
- redirect URI validation
- refreshing tokens
- Web API player endpoints and error responses
- February 2026 Development Mode limits

No Spotify client secret or Spotify iOS SDK is included. Spotify trademarks, services, and APIs remain subject to Spotify's terms and policies.

## Apple

The app uses public Apple frameworks and documentation:

- SwiftUI
- AuthenticationServices
- CryptoKit
- Security/Keychain Services
- URLSession
- XCTest

Personal Team installation instructions are based on Apple's membership comparison documentation.

## Huawei protocol references reserved for later phases

Huawei protocol code is not implemented in Phase 0–1.

When later phases begin:

- `zyv/huawei-lpv2` (MIT) may be used as the principal packet/auth/crypto reference with attribution and independent Swift implementation.
- Gadgetbridge (AGPLv3) may be used as a behavioral/protocol reference. Significant AGPL code must not be copied into this MIT project unless licensing for the whole derived work is handled accordingly.
- `madalindk/Huawei-GT2-Spotify` is only a visual reference and is not a working iPhone/Spotify bridge.

References:

- https://github.com/zyv/huawei-lpv2
- https://codeberg.org/Freeyourgadget/Gadgetbridge
- https://github.com/madalindk/Huawei-GT2-Spotify
