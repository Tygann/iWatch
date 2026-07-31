# Sync contract

- Local library actions succeed without Trakt.
- CloudKit replicates local library data across a person's devices.
- A Trakt link belongs to one Trakt account. Sync checkpoints and outbox operations are scoped to that account.
- Connecting a new account imports Trakt by default. Uploading existing local data is a separate explicit action.
- An operation remains durable until Trakt acknowledges it. Transient failures retry with backoff; authorization and validation failures require user action.
- Pulls use Trakt activity timestamps and all pages. Deletion tombstones remain until acknowledgement.
