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

1. Mac simulator builds and 96 unit tests passed on October 25; About was inspected in light/dark appearance at standard and largest accessibility sizes. See the Mac follow-up below.
2. Three genuine 13-inch iPad screenshots were captured at 2064 × 2752. Uploaded them to version 1.0’s 13-inch iPad slot; App Store Connect shows 3 of 10 screenshots.
3. Build 26 from the handoff commit has processed and replaced build 25 in version 1.0. ReleaseHistory records its source boundary. Do not submit until the remaining privacy, content-rights, and public-release gates are resolved.
4. Complete the App Privacy declaration using the provider review above.
5. Complete content rights after the updated build contains the attribution and applicable usage permissions are established. Free/non-commercial TMDB API use is subject to attribution and terms; an API integration alone does not prove a separate commercial agreement or rights to every item of artwork.

TMDB requirements: https://developer.themoviedb.org/docs/faq


## Mac follow-up — October 25, 2026

- Pulled `origin/main` with fast-forward-only; it was already at `f31797924797e382f135dab7b153e587dc328dbc`, with a clean working tree.
- XcodeBuildMCP built and launched scheme `iWatch` on iPhone 17 and iPad Pro 11-inch (M5), iOS/iPadOS 26.5. All 96 `iWatchTests` passed, including Trakt authentication and account-boundary tests.
- About was visually inspected in light/dark appearance, at standard and largest accessibility text sizes. Attribution and links wrap and remain reachable by scrolling; no app UI fix was needed.
- The existing iPadOS 27.0 screenshot simulator could not boot. Created a dedicated **iWatch App Store iPad 13**, iPad Pro 13-inch (M5), running working iPadOS 26.5; build and launch passed.
- Saved unmodified native screenshots to `~/Pictures/iWatch/AppStore/1.0/iPad13/`: `01-discover-light.png`, `02-trending-light.png`, `03-show-detail-light.png`. Each is a genuine 2064 × 2752 PNG from Device Hub, using real TMDB catalog responses and no UI-test fixtures. XcodeBuildMCP's screenshot response is a reduced preview, so Device Hub's screenshot export supplied the upload files.
- The owner completed App Store Connect sign-in on this Mac. Build 26 selection was saved later in this follow-up (see below). Privacy publication, content-rights save, and App Review submission have not been performed.

### Provider review and draft questionnaire decisions

Reviewed Apple's [App Privacy guidance](https://developer.apple.com/app-store/app-privacy-details/), [TMDB privacy policy](https://www.themoviedb.org/privacy-policy) (effective August 24, 2026), [TMDB API terms](https://www.themoviedb.org/api-terms-of-use), [TMDB FAQ](https://developer.themoviedb.org/docs/faq), and [Trakt privacy policy](https://app.trakt.tv/privacy) (displayed August 20, 2024).

Apple distinguishes retained off-device data from request-only processing. Ongoing optional sync is disclosable; Apple-only collection is not automatically the developer's collection.

| Data / answer | Supported decision | Still needed |
| --- | --- | --- |
| Data collected | Yes: Trakt retains account-linked synced library/history | Do not publish Data Not Collected |
| User ID | Trakt identifier; linked; App Functionality | Confirm additional provider purposes |
| Other User Content | Synced watchlist/library; linked; App Functionality | Confirm provider classification and additional purposes |
| Product Interaction | Synced watched history; linked; App Functionality | Trakt also describes personalization/analytics of sync activity and possible targeted ads; determine applicability to this integration |
| Search History | TMDB explicitly includes search/API data in its policy | Retention, linkage, purposes, and tracking for unauthenticated end-user API searches |
| IP / technical data | Both providers describe technical collection; classify by actual use | API retention, geolocation derivation, diagnostic/device identifier treatment |
| Device ID in private CloudKit | App-generated coordination ID exists | Establish developer-access/collection treatment separately from Apple-only collection |
| Tracking | No defensible blanket No from the absence of an ad SDK | API-specific confirmation about cross-context ads, advertising measurement, and broker sharing |

TMDB's policy covers API use and permits analysis, personalization, and advertising-related processing. Trakt explicitly discusses retained account data, sync-content personalization/analytics, and possible targeted advertising. Neither public policy isolates every practice for iWatch's exact API traffic. These are unresolved provider facts, not evidence that the app definitely tracks users or that every website cookie practice applies to native API calls. Do not add ATT or publish tracking answers based only on a guess.

Prepared questions for the owner to obtain from providers (not sent):

1. TMDB: For third-party native API/CDN calls using a developer key without end-user TMDB sign-in, which search, IP, request, and identifier data are retained; for how long; linked to whom; and for which purposes? Is any of this data used with third-party data for advertising/measurement or shared with brokers?
2. Trakt: For account-linked watchlist/history API sync, which identifiers/content/technical data are retained, and used for analytics, personalization, advertising, or cross-context advertising? Can API-origin data be excluded from advertising uses, and what defaults apply?

### Content rights and remaining release gates

The app uses third-party metadata/artwork, so a declaration that it contains no third-party content would be inaccurate. TMDB grants a conditional API/content license; its FAQ allows attributed non-commercial use, while commercial revenue use requires a separate written agreement. Confirm the app's actual commercial intent and any applicable written permissions before saving the rights attestation. Free App Store pricing alone does not settle indirect commercial use. The API terms also restrict caching TMDB information beyond six months; verify the persisted metadata/cache lifecycle or obtain applicable permission before attesting compliance. Keep user-authored library/history distinct from provider metadata when assessing retention.

Before upload/submission, reconcile the repository's release gates:

- `Docs/TRAKT_CONFIGURATION.md` requires a clean Release archive with valid configuration and real-device OAuth, import, refresh, and reconnect verification before uploading; Simulator unit tests do not establish these results.
- `Docs/CLOUDKIT_RELEASE_CHECKLIST.md` requires Production schema verification and physical-device replication/reset checks.
- `Docs/NEXT_STEPS.md` records migration of Trakt's custom URL callback to Universal Links before public release; confirm completion or explicitly resolve that release requirement with the owner.
- Once the checks and sign-in are resolved, upload a uniquely numbered build greater than 25, wait for processing, and attach it to the version 1.0 listing. Record the actual uploaded source commit/build in ReleaseHistory only after confirmation. Stop before submitting for App Review.


Owner clarification: iWatch is currently free; a premium option may be added later. The owner has only the public TMDB/Trakt terms, with no separate written provider permissions. Reassess TMDB commercial licensing before introducing premium, ads, subscriptions, or other revenue use. The current free release still needs to satisfy the public license conditions. The owner confirmed that the required physical-device Trakt and two-device CloudKit replication/reset checks passed.


### Mac verification and listing result

- Added four About UI checks (light/dark, standard/largest accessibility text) that require the TMDB, privacy, and support links to remain reachable and retain screenshot attachments. Reviewed the exported light/dark screenshots. Corrected an existing Settings UI test to use the native Appearance menu; all five focused UI checks passed.
- About QA attachments are under `~/Pictures/iWatch/AppStore/1.0/AboutQA/` and `AboutQA-Dark/`; the dark rerun is the authoritative dark-appearance evidence.
- Uploaded the three PNGs to version 1.0, English (U.S.), **iPad 13-inch display**. Apple showed all three filenames and `3 of 10 App Screenshots`; existing iPhone screenshots were preserved. Local proof: `~/Pictures/iWatch/AppStore/1.0/ipad-upload-confirmation.jpg`.
- Saved an **unpublished, incomplete** App Privacy draft with Other User Content, Search History, User ID, and Product Interaction. Additional types and per-type purpose/linkage/tracking answers still require the provider review above. Publish remains disabled; no privacy label was published. Local proof: `~/Pictures/iWatch/AppStore/1.0/privacy-draft-confirmation.jpg`.
- Inspected Apple's exact content-rights question. The Yes answer also attests necessary rights; No is inaccurate for iWatch. Left it unset pending resolution of the conditional TMDB license/cache review and applicable permissions.
- The owner confirmed the required physical-device Trakt and two-device CloudKit checks passed. This is owner-supplied verification, separate from the Simulator evidence above.


### Build 26 completion and resumed handoff

- Xcode Cloud had automatically archived and uploaded `f31797924797e382f135dab7b153e587dc328dbc` as build 26 on October 25, 2026. Its archive succeeded with Xcode 27.2 RC; TestFlight showed **Ready to Submit**. Reused this exact validated product commit rather than creating a redundant upload for test/documentation-only changes.
- Replaced build 25 with build 26 in version 1.0 and saved. Proof: `~/Pictures/iWatch/AppStore/1.0/build-26-selection.jpg`.
- Saved the focused What to Test copy recorded in ReleaseHistory; TestFlight showed **Saved**. Proof: `~/Pictures/iWatch/AppStore/1.0/build-26-test-notes.jpg`.
- Final light-mode UI rerun also passed both standard/accessibility checks after using the integer AppTheme preference, completing validation of the final test source. All five focused UI checks and 96 unit tests passed; no application Swift changes were necessary.
- On resumption, local browser use was disabled in Work settings, preventing fresh live verification or further questionnaire edits. The listing results above were verified in the preceding pass, not rechecked after resumption.

Remaining blockers before App Review:

1. Finish and publish accurate App Privacy purpose/linkage/tracking answers after resolving the API-specific provider practices described above. The saved four-category draft is incomplete, including any additional technical-data categories.
2. Resolve content rights under the public TMDB/Trakt terms. In particular, the inspected code refreshes persisted metadata opportunistically and can serve cached records during failures; a six-month hard expiry was not established. Confirm compliant retention or obtain permission before making the necessary-rights attestation. Never erase user library/history to solve provider-cache retention.
3. Resolve the pre-public-release Universal Links callback item in `Docs/NEXT_STEPS.md`; it is distinct from the owner-confirmed physical-device tests.
4. Confirm Production CloudKit schema readiness under `Docs/CLOUDKIT_RELEASE_CHECKLIST.md`. The owner confirmed device checks; a separate live Production schema inspection was not performed in this pass.

No App Review submission was made. Future premium monetization requires reassessing commercial API licensing before activation.


### Additional preparation — October 25, 2026

- Browser access restored. Exported **Production** schema from CloudKit Console for team `XKQ424HQ33`, container `iCloud.com.tyler.iWatch`, to `~/Downloads/cloudkit-production.ckdb`. Ran `python3 Scripts/check-cloudkit-schema.py --schema ~/Downloads/cloudkit-production.ckdb`: **CloudKit Production schema covers 8 SwiftData models**. No schema deployment, data query, token creation, or user-record modification was needed. This resolves the schema-structure verification item; owner-confirmed physical-device checks remain separate evidence.
- Reviewed Trakt's current [API Use Policy](https://developer.trakt.tv/docs/api-use-policy). It explicitly permits user watchlist/history integrations in free and paid apps without separate written approval, subject to the policy. Lack of a separate Trakt commercial contract is therefore not itself a blocker. TMDB's distinct terms still apply to TMDB-sourced metadata/artwork.
- The Trakt policy requires the notice `iWatch uses Trakt but is not endorsed or certified by Trakt.` in About and the app-store description. Added a Trakt link/notice in About and appended the notice to the existing App Store description. Saved the listing copy; all original description text was retained. Proof: `~/Pictures/iWatch/AppStore/1.0/trakt-store-attribution.jpg`.
- Trakt Developer shows the existing iWatch application as **Approved**, using `com.tyler.iWatch://oauth/callback`. Settings are read-only until the owner connects GitHub. Requested that prerequisite; no live API credentials were revealed, modified, or copied.
- Trakt's current [PKCE guide](https://developer.trakt.tv/docs/pkce) recommends S256 PKCE plus HTTPS redirects backed by Universal Links; the present implementation uses state and a bundled client secret. Coordinate PKCE, HTTPS callback handling, website association, and registered redirect together. Do not switch the live redirect before the app/domain path is ready and physically verified.

- The additional Trakt attribution passed a Simulator build and all 100 selected tests (96 unit + four About UI variants). Exported and visually reviewed standard/accessibility light/dark screenshots under `~/Pictures/iWatch/AppStore/1.0/TraktAttributionQA/`.
- With the owner's authorization, started the Trakt GitHub connection. It requires GitHub sign-in in the browser; requested owner login. No credentials were entered or revealed.


### HTTPS / PKCE implementation follow-up

- With explicit owner authorization, published website commit `2c4345b` in Portfolio. Live `https://tylerkeegan.com/.well-known/apple-app-site-association` returned HTTP 200 and application/json; it names only `XKQ424HQ33.com.tyler.iWatch`, limits applinks to the Trakt callback, and provides Apple's webcredentials association. The fallback page uses no scripts, does not reflect query values, and sends no-referrer/no-store headers.
- Owner connected GitHub to Trakt Developer. Added `https://tylerkeegan.com/iwatch/oauth/trakt` to iWatch's allowed redirects and verified it alongside the legacy URI. Existing users can still use the old build's redirect. No live credentials were revealed or changed.
- Prepared app migration: Apple's HTTPS authentication callback, associated domains, fresh S256 PKCE per attempt, verifier cleanup on completion/cancel/disconnect, and secret-free token exchange/refresh. The build phase strips the legacy client secret from built plists only and migrates the known old redirect to HTTPS; local Secrets.plist remains untouched.
- Final Simulator build and 97 unit tests passed, including account-boundary/authentication tests and legacy redirect migration. Configuration fixture tests pass, including no bundled client secret, legacy migration, HTTPS acceptance, and invalid redirect rejection. Website build and five build checks passed.
- **Do not push/upload the authentication commit to main's automatic archive workflow until physical-device HTTPS sign-in, callback, token exchange, import, refresh, and reconnect are verified.** Prior owner-confirmed tests were for the old flow and do not validate these new changes. Keep the legacy registration until compatibility is no longer needed.
- Saved proof: `~/Pictures/iWatch/AppStore/1.0/trakt-https-registration.jpg`, `oauth-fallback-preview.jpg`, and `cloudkit-production-schema.jpg`.

- Build 27 from `3e3e6cc0354228d815bb719275b9dfab67593c63` archived successfully, processed as Ready to Submit, and replaced build 26 in the saved version 1.0 listing. Screenshot: `~/Pictures/iWatch/AppStore/1.0/build-27-selection.jpg`. It contains Trakt attribution, not the later local authentication migration.

### Cache-retention implementation — October 25, 2026

- Added a replicated retention origin to MediaRecord/EpisodeRecord, independent of mutable edit timestamps. Catalog metadata expires after 150 days; unknown legacy provenance expires immediately on inspection. Duplicate merging keeps the oldest origin. Metadata reads/writes, snapshot reads, and launch/foreground maintenance remove expired provider rows without removing watchlists, watched history, dispositions, generations, or outbox records.
- Bounded artwork retention to 30 days, including synchronous decoded-image reuse, and disabled API HTTP-response caching after clearing the legacy cache. Snapshot reuse is limited to 60 seconds. A dormant app checks expiry when it runs again; offline expired metadata does not receive an unlimited fallback.
- Added and deployed only `CD_metadataCachedAt TIMESTAMP` on CD_MediaRecord and CD_EpisodeRecord. Production schema exported from the Console passes the eight-model checker. No Console user-record edits or security-role changes were made. Proof: `~/Pictures/iWatch/AppStore/1.0/retention-schema-deployed.jpg`.
- Simulator build and 100 unit tests passed during verification; see `RELEASE_HANDOFF.md` for physical-device checks and the distribution boundary. Owner chose to test the new flow locally later. Keep the new commits local until those checks pass; build 27 does not include them.
- App Privacy and the content-rights attestation remain unpublished/unset. Implementation addresses the identified cache-lifecycle gap but does not establish provider-side privacy facts or a commercial TMDB license.
