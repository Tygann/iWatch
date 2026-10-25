# CloudKit release checklist

Before submitting iWatch, verify the `iCloud.com.tyler.iWatch` container in CloudKit Console:

- Development schema contains every current SwiftData record type and is deployed to Production.
- The app identifier has iCloud/CloudKit and Push Notifications enabled; Background Modes includes Remote notifications.
- A signed build on two physical devices using the same iCloud account propagates watchlist, watched-history, and deletion changes in both directions.
- Disconnecting Trakt does not affect CloudKit replication; connecting Trakt on each device does not cross account boundaries.
- A production TestFlight build is tested with a real Trakt account for OAuth redirect, import, upload, background retry, and reconnect flows.
- Supply private Trakt build configuration as described in `TRAKT_CONFIGURATION.md`; confirm the clean Release archive passes the Configure Trakt phase before uploading.
- Reset is tested while another device is offline; after that device reconnects, its older library generation does not repopulate the reset library.
- Reset progress reports local deletion separately from a successful CloudKit export, and an interrupted confirmation can be retried after relaunch.

CloudKit is asynchronous. Do not add manual polling to replace the system's normal replication behavior; instead, make local UI observe the SwiftData store and validate the actual device-to-device result.

## Automated schema preflight

Xcode Cloud Release builds run `scripts/check-cloudkit-schema.py --live` from the
configuration phase. Add `CLOUDKIT_MANAGEMENT_TOKEN` as a private workflow
variable, generated in CloudKit Console > account Settings > CloudKit Management
Tokens for the developer team. Track its expiration and replace it privately
before it expires. This token is only used by cktool and is never bundled in the
app. A failed export or missing/mistyped required field stops the build; the
check never deploys or modifies a schema.

The checker derives the eight current model types and stored fields from source.
Extra Production fields are allowed. Changes to SwiftData mappings or unsupported
stored types require reviewing the checker too. CI runs its portable self-test.
For a local check without credentials, export the Production schema from the
Console and run:

```sh
python3 scripts/check-cloudkit-schema.py --schema /path/to/production.ckdb
```

A passing schema check verifies structure, not permissions, replication, or device
behavior. The physical-device checks above remain required.
