# CloudKit release checklist

Before submitting iWatch, verify the `iCloud.com.tyler.iWatch` container in CloudKit Console:

- Development schema contains every current SwiftData record type and is deployed to Production.
- The app identifier has iCloud/CloudKit and Push Notifications enabled; Background Modes includes Remote notifications.
- A signed build on two physical devices using the same iCloud account propagates watchlist, watched-history, and deletion changes in both directions.
- Disconnecting Trakt does not affect CloudKit replication; connecting Trakt on each device does not cross account boundaries.
- A production TestFlight build is tested with a real Trakt account for OAuth redirect, import, upload, background retry, and reconnect flows.
- Reset is tested while another device is offline; after that device reconnects, its older library generation does not repopulate the reset library.
- Reset progress reports local deletion separately from a successful CloudKit export, and an interrupted confirmation can be retried after relaunch.

CloudKit is asynchronous. Do not add manual polling to replace the system's normal replication behavior; instead, make local UI observe the SwiftData store and validate the actual device-to-device result.
