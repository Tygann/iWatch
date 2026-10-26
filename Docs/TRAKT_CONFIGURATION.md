# TMDb and Trakt build configuration

Trakt credentials belong to the iWatch Trakt application, not the person signing
in. Obtain valid credentials from that application's owner. Do not commit them.

For local builds, copy `iWatch/Secrets.example.plist` to the ignored
`iWatch/Secrets.plist` and replace the placeholder values privately. Xcode's
synchronized app folder includes the local file as a bundle resource.

TMDb supplies movie/show metadata and artwork independently of Trakt. Configure
`TMDB_API_KEY` with a TMDb v3 API key (not the API Read Access Token).
Keep it in the ignored local plist for local builds.

For CI and Xcode Cloud, configure private environment variables
`TMDB_API_KEY`, `TRAKT_CLIENT_ID`, and `TRAKT_REDIRECT_URI` in the build service. Make them available to the archive action. The Configure Trakt phase
places these values into the app build product without changing the source
Secrets.plist. Use `main` as the workflow source branch. Local Xcode does not
inherit Xcode Cloud variables; keep the ignored local file for local builds.
When a variable is supplied, it overrides the corresponding local value.
Keep shell tracing disabled and never print these variables.

The HTTPS redirect is `https://tylerkeegan.com/iwatch/oauth/trakt`.
That value is registered in Trakt and the website association is deployed.
The build phase migrates the known legacy callback in its output without editing
local credential files; unknown callback values fail Release validation. The app supports
Apple's HTTPS authentication callback and declares both applinks and webcredentials
for tylerkeegan.com. Keep the legacy `com.tyler.iWatch://oauth/callback` registration
until the new flow has passed physical-device sign-in/reconnect verification.
New builds default to the HTTPS callback. Physical-device verification is still
required before uploading this authentication change.

OAuth uses a fresh in-memory S256 PKCE verifier for each attempt; state and verifier
are discarded after completion, cancellation, or disconnect. Token exchange and
refresh do not send a client secret. The build phase removes TRAKT_CLIENT_SECRET
from both built plists even if older local/CI inputs still contain it, without
editing the local source file. Remove obsolete CI configuration privately when
convenient. Never print or commit credentials.

Every Release build and archive validates the effective configuration in the
built app. Missing, whitespace-only, placeholder, or unresolved values stop the
build. TMDb is also required and validated for Release builds, preventing a
missing key from reaching TestFlight. This validates configuration presence,
not whether the provider has revoked a key. Debug builds can omit remote
configuration so local library development and unit tests remain available. The phase runs on every build and reconstructs API
configuration from the current local file and environment, so removed inputs cannot reuse old values
from an incremental build. API keys in the generated Info.plist are owned by
this phase; configure them through these two inputs. App-target script
sandboxing is disabled so it can update build-product configuration using private
environment variables. This does not change the app's runtime sandbox.

Before publishing, use a clean Release archive with the intended private
configuration, then verify sign-in, callback, initial import, token refresh, and
reconnect on a device. Never upload an archive that has not passed this check.
Credentials embedded in a native app can be extracted; build-service secret
storage protects the repository and logs, not the distributed binary.

Changing these inputs requires rebuilding and distributing the app. An installed
build with missing configuration cannot be repaired by retrying Connect.

Run `python3 scripts/test-trakt-configuration.py` to check configuration behavior.
On macOS this exercises Apple's real plist tools; other hosts use substitutes.

CloudKit schema verification uses a separate private workflow variable,
`CLOUDKIT_MANAGEMENT_TOKEN`. See `CLOUDKIT_RELEASE_CHECKLIST.md` for setup and
rotation. It is not an app API credential and must never go in Secrets.plist.
