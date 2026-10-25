# Library, provider, and cloud flow

SwiftData is the library's source of truth. Its private CloudKit store replicates
library records and outbox records across devices. Trakt is an optional external
account; TMDb supplies metadata independently of Trakt authentication.

## Local edits and Trakt

LibraryRepository saves a library edit and its outbox operation together. An
operation payload records its originating device and mutation timestamp. The
account and library generation remain explicit boundaries on the record.
Coalescing applies only to pending operations for the same account, generation,
and originating device. Integrity repair merges replicas of the same operation
identity, never different operations merely because they mention the same title.

Only the originating device automatically uploads an operation. A process-local
claim prevents overlapping engines on that device from sending it together;
CloudKit replication is not used as a distributed lock. A response acknowledges
library state only when no newer local edit or other unfinished operation would
be overwritten. Account or reset changes abort work before merging responses.

Older payloads without device ownership remain pending until explicit recovery.
Settings > iCloud Sync > Recover Pending Uploads on This Device transfers
unfinished work for the selected account, including unlinked work, after user
confirmation. Stop syncing on the previous device first. Watched-history additions snapshot matching remote IDs before sending and persist
an uncertainty marker before the POST. After a lost response, retries only read
remote history and identify a unique new ID; they never blindly resend the play.
Existing plays in the same second cannot confirm the new upload. Missing evidence,
legacy requests without a baseline, or multiple matches remain unresolved for
manual review. This favors correctness over automatic completion; Trakt does not
provide an idempotency key, so concurrent external edits can still be ambiguous.

Removing an unsent local play cancels its pending addition. Removing a play during
an upload retains a tombstone and queues deletion until the remote history ID is
confirmed. Separate remote history IDs remain distinct even within one second.

Local edits trigger incremental sync rather than a full history reconciliation.
Explicit Sync Now reconciles full history. Foreground/background runs also do a
full reconciliation when the device-local, account-specific checkpoint is at
least a day old. This catches backdated additions and remote removals without
redownloading all history after each edit.

## CloudKit and screen updates

The cloud monitor observes completed imports and ongoing/completed exports
independently of Trakt. Imports debounce snapshot invalidation and advance the
session revision, refreshing visible library screens and notification scheduling.
Diagnostics retain separate last-download and last-upload times. Export events
provide evidence of an export, not confirmation that every other device has
received the data. Nested failures are summarized without record IDs or payloads.

Trakt-derived library reset removes records from the shared store; those
deletions can propagate through iCloud. It is not a device-only cache purge.

## Metadata and network work

Detail freshness is device-local and separate from library/search timestamps.
Cached complete details appear immediately; stale details refresh in the
background (6 hours for upcoming titles, 12 hours for ongoing shows, and 7 days
for released movies or ended shows). Rich episode details also refresh after
12 hours while preserving the cached view. Failed background refreshes
retain cached data and are throttled for a minute. Season data has a 12-hour
freshness window and retains cached episodes on a non-forced refresh failure.
The bounded fetch-date cache is cleared with other on-device caches.

Identical concurrent GET requests share one network task; request headers,
including authorization, participate in identity. Writes never share tasks.
Trakt token refreshes share one task, and token writes/clears are ordered so a
late refresh cannot restore a disconnected session. Debug URL logging omits
queries, fragments, and user information.

## Verification

Run the complete iWatchTests suite and the two sync diagnostics UI tests at
standard and accessibility text sizes through XcodeBuildMCP. Regression coverage
includes account/device ownership, explicit recovery, acknowledgement during a
new edit, repair identity, cloud-driven invalidation without Trakt, periodic
reconciliation, fetch freshness, concurrent requests, and refresh/disconnect races.

Before trusting multi-device behavior, use two physical devices with the same
iCloud account: edit on each while the other is offline, reconnect, confirm
library convergence, and check that watched plays are not uploaded twice. Verify
recovery with syncing stopped on the originating device. Do not delete a store
or reset data to work around a failed verification.

## Snapshot performance baseline

`LibraryPerformanceTests.testRepresentativeLibrarySnapshotBaseline` seeds an
isolated in-memory store with 49 movies, 32 shows, 640 episodes and 5,105 plays.
On October 25, 2026, an isolated Debug run on the iPhone 18 Pro simulator measured
movie snapshots at 17.4–17.7 ms and show snapshots at 98.4–111.4 ms across three
runs. The test retains a timing attachment and checks result counts; it does not
impose a machine-dependent timing threshold. These synthetic measurements are
not real-device launch, scrolling, network, or CloudKit measurements. Profile a
physical device with the real library before adding cache invalidation complexity.
