# Next steps

- Before public release, migrate Trakt OAuth from the custom URL scheme to an HTTPS callback on an owned domain using iOS Universal Links. Trakt's developer portal warns that other apps can claim the current scheme and intercept authorization codes. Configure the domain's apple-app-site-association file and app Associated Domains entitlement, update authentication callback handling and the release configuration validator, then update the registered Trakt redirect together. Verify sign-in, callback, token exchange, and reconnect on a device before removing the old redirect.
- Capture before/after SwiftUI and Time Profiler traces on a physical device with a production-sized library; use the trace to decide whether poster glass effects or context menus need further simplification.
- Rotate TMDb and Trakt credentials after the secrets migration.
- Verify Trakt authorization, account linking, and background sync on a physical device.
