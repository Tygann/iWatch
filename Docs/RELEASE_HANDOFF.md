# First-release handoff — October 25, 2026

## Current distribution boundary

App Store Connect version 1.0 selects build 27, sourced from
`3e3e6cc0354228d815bb719275b9dfab67593c63`. Its What to Test is saved.
The genuine 13-inch iPad assets are uploaded. No App Review submission was made.
See `releases/ReleaseHistory.md` for uploaded-build history.

Local commits after that boundary prepare HTTPS/PKCE authentication and provider
cache retention. They have not been pushed because main automatically uploads
through Xcode Cloud, and the new physical-device authentication check is pending.
The owner elected to perform that check locally later.

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

After recording results, push the validated commits, allow Xcode Cloud to upload,
verify processing and signing, select the new build, and record its actual source
commit/build in ReleaseHistory. Do not assume build 27 contains these changes.

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

## Unresolved declarations

The App Privacy draft remains unpublished. The known account-linked sync data is
recorded in `APP_STORE_PRIVACY_REVIEW.md`; API-specific retention, linkage,
purposes, and advertising/tracking practices still need authoritative answers.
Do not infer those answers from a lack of advertising SDKs.

The content-rights attestation is still unset. Attribution is implemented and
cache expiry is prepared, but the distributed build must include it before
attesting compliance. TMDB's non-commercial allowance depends on actual purpose,
not only free pricing; reassess commercial licensing before premium monetization.
Trakt's public API Use Policy permits this type of free/paid integration without
individual written approval, subject to its requirements.

Do not submit for App Review until these declarations and physical verification
are resolved.
