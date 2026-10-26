# App Store privacy and release follow-up

Reviewed October 25, 2026 against source baseline `add0a72bc0d040cc24f8efab358831ff37a07c93`. Website policy: https://tylerkeegan.com/iwatch/privacy/

## Verified data flows

| Data | Destination and purpose | Source |
| --- | --- | --- |
| Library titles, watchlists, watched dates, episode progress | Local SwiftData storage; private CloudKit replication when iCloud is available | `Data/Local/Persistence.swift`, library record models |
| Trakt account identifier and sync bookkeeping | Local/private CloudKit records to isolate account sync and coordinate devices | `Data/Local/LocalStore.swift`, `Data/Repositories/SyncRepository.swift` |
| Random app-generated device identifier | Keychain and sync coordination records; not an advertising identifier | `Platform/Services/AuthService.swift`, `Domain/Protocols.swift` |
| Trakt OAuth access/refresh tokens | Device Keychain; authorized requests directly to Trakt | `Platform/Services/AuthService.swift`, `Data/Remote/Trakt/TraktClient.swift` |
| Optional Trakt watchlist and history, title IDs, watched timestamps | Trakt account import/upload and subsequent sync | `Features/Settings/TraktSettingsView.swift`, `Data/Remote/Trakt/TraktClient.swift` |
| Search text, requested title/person/episode IDs, artwork paths | TMDB API/CDN for catalog functionality | `Data/Remote/TMDb/TMDbClient.swift`, `Platform/Services/ImageURLBuilder.swift` |
| Country/region code from device locale | TMDB provider discovery; not GPS access | `Features/Browse/ProviderBrowseView.swift`, `Data/Remote/TMDb/TMDbClient.swift` |
| Release reminder titles/dates | Local notifications after notification permission | `Platform/Notifications/ReleaseNotificationCoordinator.swift` |

No advertising/third-party analytics SDK, advertising-ID access, GPS permission request, or iWatch-operated app backend was found in the reviewed code. This does not establish that Apple or external API providers collect no information. The website separately receives technical requests, and support email/TestFlight feedback can contain information users send.

## App Privacy questionnaire worksheet — not a published declaration

Apple requires disclosure of applicable third-party collection, including app functionality. Optional ongoing sync is not automatically exempt merely because connecting the account is optional.

Known data to evaluate before submitting the label:

- **User ID:** Trakt account identifier, associated with account-linked sync.
- **Other User Content:** User-created watchlist/library entries sent to Trakt.
- **Product Interaction / Other Usage Data:** Watched history and API usage, classified according to Apple's current definitions and the provider's actual handling.
- **Search History:** Searches are sent to TMDB; its published privacy policy specifically covers API use and search-related data.
- **Other Data or relevant identifiers:** Providers receive IP/technical request information. Determine how those are retained, associated, and used before assigning categories and linkage. A locale country code alone should not be described as GPS location.
- **Device ID:** An app-generated coordination identifier is present in private CloudKit records. Evaluate its disclosure treatment separately from Apple's advertising identifier; do not claim there is no device identifier at all.

App code demonstrates app-functionality purposes. It cannot establish every provider-side analytics, personalization, marketing, retention, linkage, or tracking practice. Do not mark every category as “not linked” or “not used for tracking” solely because the app has no advertising SDK. Do not classify visiting an external browser link as an embedded SDK without checking Apple's guidance.

Before publishing, resolve which provisions of the providers' general policies apply specifically to these API requests and linked-account sync. Finalize category, purpose, identity linkage, and tracking answers accordingly. Until then, the App Privacy questionnaire remains incomplete; no “Data Not Collected” claim has been published.

References:

- https://developer.apple.com/app-store/app-privacy-details/
- https://www.themoviedb.org/privacy-policy (explicitly includes API usage and search/technical data)
- https://trakt.tv/privacy

## Prepared app changes and verification

- About shows the approved TMDB logo and required API/non-endorsement notice, plus privacy/support links and developer copyright.
- Removed the log statement that serialized Trakt access and refresh tokens to console output. No live tokens were inspected, printed, changed, or revoked.
- The logo is an unmodified official SVG rasterized into an original-color asset; provenance is in `Design/Attribution/README.md`.
- `git diff --check` passes. XcodeBuildMCP could not list simulators on this Windows host (`spawn xcrun ENOENT`). Swift build/tests and standard/accessibility-size Simulator checks have not run. The user explicitly requested committing and pushing these changes to `main` for transfer to a new Mac chat, with Mac verification deferred until that transfer. This is a task-specific exception to the usual pre-commit checks, not a change to the repository's ongoing verification requirements.

## Remaining release actions

1. On a Mac, build scheme `iWatch`, run affected unit tests, and verify About in light/dark appearance and standard/accessibility text sizes.
2. Capture genuine 13-inch iPad screenshots at an accepted size (2048 × 2732 or 2064 × 2752 portrait, or landscape equivalents).
3. After Mac checks pass, fix and commit any issues found, upload the updated build, and attach it to version 1.0. The currently attached build 25 does not contain these changes.
4. Complete the App Privacy declaration using the provider review above.
5. Complete content rights after the updated build contains the attribution and applicable usage permissions are established. Free/non-commercial TMDB API use is subject to attribution and terms; an API integration alone does not prove a separate commercial agreement or rights to every item of artwork.

TMDB requirements: https://developer.themoviedb.org/docs/faq
