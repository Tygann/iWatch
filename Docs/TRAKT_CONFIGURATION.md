# Trakt build configuration

Trakt credentials belong to the iWatch Trakt application, not the person signing
in. Obtain valid credentials from that application's owner. Do not commit them.

For local builds, copy `iWatch/Secrets.example.plist` to the ignored
`iWatch/Secrets.plist` and replace the placeholder values privately. Xcode's
synchronized app folder includes the local file as a bundle resource.

For CI and Xcode Cloud, configure private environment variables
`TRAKT_CLIENT_ID`, `TRAKT_CLIENT_SECRET`, and `TRAKT_REDIRECT_URI` in the build
service. Make them available to the archive action. The Configure Trakt phase
places these values into the app build product without changing the source
Secrets.plist. Use `main` as the workflow source branch. Local Xcode does not
inherit Xcode Cloud variables; keep the ignored local file for local builds.
When a variable is supplied, it overrides the corresponding local value.
Keep shell tracing disabled and never print these variables.

Use `com.tyler.iWatch://oauth/callback` as the redirect and register that exact
value in the Trakt application's settings. When omitted, the redirect defaults
to the bundle identifier followed by `://oauth/callback`.

Every Release build and archive validates the effective configuration in the
built app. Missing, whitespace-only, placeholder, or unresolved values stop the
build. Debug builds can omit Trakt so local library development and unit tests
remain available. The phase runs on every build and reconstructs Trakt
configuration from the current local file and environment, so removed inputs cannot reuse old values
from an incremental build. Trakt keys in the generated Info.plist are owned by
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
