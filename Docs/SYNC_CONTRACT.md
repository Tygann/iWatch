# Sync contract

- Local library actions succeed without Trakt.
- CloudKit replicates local library data across a person's devices.
- A Trakt link belongs to one Trakt account. Sync checkpoints and outbox operations are scoped to that account.
- Connecting a new account imports Trakt by default. Uploading existing local data is a separate explicit action.
- Resetting or replacing a library advances a CloudKit-replicated generation. Records from an older generation must never repopulate the active library when an offline device reconnects.
- A reset is complete on-device after the local transaction saves, but the UI must not claim iCloud completion until a subsequent successful CloudKit export is observed.
- An operation remains durable until Trakt acknowledges it. Transient failures retry with backoff; authorization and validation failures require user action.
- Pulls use Trakt activity timestamps and all pages. Deletion tombstones remain until acknowledgement.
