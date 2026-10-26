# First-release handoff — October 25, 2026

## Current distribution boundary

App Store Connect version 1.0 selects build 29, sourced from
`6b8370a41bde543b637326f0123c7cb781ca3bcf`. Its What to Test is saved.
The genuine 13-inch iPad assets are uploaded. The revised 3840 × 1646 vector
header, using the owner-supplied actual icon and blue gradient, was uploaded
on October 26, 2026, visually checked in App Store Connect,
and confirmed to persist after reload. Source and export are in
`Design/AppStore/Header/`; evidence is
`~/Pictures/iWatch/AppStore/1.0/header-uploaded.png`.
No App Review submission was made.
See `releases/ReleaseHistory.md` for uploaded-build history.

The owner confirmed the new physical-device Trakt checks passed and authorized
proceeding. Authentication/cache source was pushed to main. Xcode Cloud build 28
compiled/archived but failed export because automatic signing could not enable
Associated Domains. Enabled that capability for com.tyler.iWatch on team
XKQ424HQ33, then clean build 29 passed distribution export and uploaded. TestFlight
showed Ready to Submit; version 1.0 now selects build 29 and its tester notes are
saved. Build 28 was not uploaded. No App Review submission was made.

## Local physical-device check

Open `iWatch.xcodeproj`, select scheme iWatch and the connected device, and run the
current checkout with automatic signing for team XKQ424HQ33. Preserve the existing
library and local Secrets.plist. The build phase migrates the known old callback
in the built product and strips the bundled client secret; do not edit credentials.

1. Confirm provisioning contains `applinks:tylerkeegan.com` and
   `webcredentials:tylerkeegan.com`.
2. Connect Trakt. Complete authorization and confirm the HTTPS callback returns
   to iWatch, token exchange succeeds, and the expected account imports.
3. Cancel a second connection attempt and retry; verify cancellation and state
   handling do not leave the app stuck or connect the wrong account.
4. Verify token refresh, disconnect, reconnect, and a watchlist/history upload.
   Never copy tokens or credential-bearing logs into the test report.
5. Confirm existing library/history survives the metadata migration. Old catalog
   rows with unknown provenance are discarded; online enrichment restores titles,
   artwork, and episode catalogs. Offline placeholders are expected until refresh.
6. Recheck two-device CloudKit replication with the new schema and metadata
   migration; verify library/history survives and account boundaries remain intact.

The owner-confirmed Trakt checks, upload, build selection, and ReleaseHistory
record are complete. The earlier owner-confirmed two-device CloudKit checks and
Production schema verification are separate evidence; no new two-device result
was claimed in the latest Trakt-only confirmation.

## Cache retention implementation

MediaRecord and EpisodeRecord have a replicated `metadataCachedAt` retention
origin. Metadata expires after 150 days; unknown legacy/future dates expire on
inspection. Search edits, sync edits, airtime enrichment, and partial refreshes do
not extend this date. Duplicate merging keeps the oldest origin. Cleanup occurs
at launch/foreground and before catalog reads/writes and library snapshot reads.
Failures propagate from metadata reads, preventing expired offline fallback.
Watchlist, watched-history, disposition, generation, and outbox rows are retained.

Artwork disk/decoded caches expire on a 30-day epoch, with decoded entries also
checking age on synchronous lookup. Legacy artwork is cleared on first use.
The API client clears its legacy URL cache and disables HTTP response caching;
SwiftData owns persistent catalog caching. Snapshot reuse is limited to 60 seconds.
The app cannot execute cleanup while it is not running; it checks again on resume.

CloudKit's Development and Production schemas contain the two additive
`CD_metadataCachedAt TIMESTAMP` fields. No existing fields, indexes, security
roles, or user records were changed through the Console. Exported Production
schema passed the checker for all eight models. Evidence is in
`~/Pictures/iWatch/AppStore/1.0/cloudkit-retention-production.ckdb` and
`retention-schema-deployed.jpg`.

## Declaration status

The revised App Privacy declaration was published on October 26, 2026 after
the owner confirmed Apple’s publication statement. Following public-source research, all
four existing categories now say No tracking and omit Third-Party Advertising.
Identity linkage, App Functionality, Analytics, and Product Personalization
remain. This is the best-supported assessment for the current integration, not a
provider-specific backend guarantee. See the superseding assessment and sources
in `APP_STORE_PRIVACY_REVIEW.md`. General website advertising language alone is
not a sufficient basis for declaring that native API requests perform tracking.
App Store Connect showed Published by Tyler Keegan, including after reload.
No App Review submission has been authorized.

The content-rights answer was saved as Yes, necessary rights to third-party
content, based on the public conditional API licenses for the current free use,
implemented attribution, and bounded cache retention. The selected build 29 contains the cache changes. TMDB's non-commercial allowance depends on actual purpose,
not only free pricing; reassess commercial licensing before premium monetization.
Trakt's public API Use Policy permits this type of free/paid integration without
individual written approval, subject to its requirements.

Do not submit for App Review without the owner’s final authorization.
