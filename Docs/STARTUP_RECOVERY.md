# Library startup and recovery

`Persistence` propagates model-container opening failures. Live bootstrap opens the same `iWatch` configuration and CloudKit container as before, on a detached task, then constructs app services on the main actor. `AppStartupController` publishes the app container only after opening succeeds and prevents overlapping retries. Background refresh must also wait for startup before using repositories or sync services.

When opening fails, the app presents Retry and Contact Support. It does not create an empty replacement, switch to an in-memory library, delete a store, clear account state, or send pending uploads. A retry opens the same configured store. Error presentation uses typed error codes and does not expose paths, provider response bodies, or record contents.

Do not copy, delete, or swap SQLite stores or their journal files as automatic recovery. Any future migration or restore feature needs a separate reviewed design that preserves library history, outbox ownership, and CloudKit consistency. In-memory containers used by tests and previews are isolated fixtures, never a fallback for live startup.

`StartupRecoveryTests` covers failed-open retry, concurrent retry suppression, safe error presentation, preservation of an invalid store file, and reopening a real temporary store without losing watched history or its account-bound outbox. Disk tests use unique temporary directories with CloudKit disabled. Simulator tests exercise the recovery screen at standard and accessibility text sizes without opening a live store.
