# Next steps

- HTTPS Trakt callback and S256 PKCE are prepared in source. The website association is live and both HTTPS/legacy redirects are registered. Before distributing this authentication change, verify fresh sign-in, HTTPS callback, token exchange, import, refresh, and reconnect on a physical device; then remove the old redirect when legacy-build compatibility is no longer needed. See `Docs/TRAKT_CONFIGURATION.md`.
- Capture before/after SwiftUI and Time Profiler traces on a physical device with a production-sized library; use the trace to decide whether poster glass effects or context menus need further simplification.
- Rotate TMDb and Trakt credentials after the secrets migration.
- Verify Trakt authorization, account linking, and background sync on a physical device.
