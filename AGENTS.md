# iWatch agent guidance

## Scope and architecture

- iWatch is a local-first SwiftUI app. SwiftData/CloudKit owns cross-device library replication; Trakt is an optional external account sync.
- Keep SwiftUI views thin. Put library mutations in `LibraryRepository`, remote sync orchestration in `SyncEngine`, and provider HTTP details in `Core/Remote`.
- Treat the Trakt account key as a hard sync boundary. Never send one account's outbox rows to another account.

## Safety

- Never print, commit, or modify live credentials. `iWatch/Secrets.plist` is local-only; use `Secrets.example.plist` as its public template.
- Do not delete or reset a SwiftData/CloudKit store as automatic error recovery.
- Preserve unrelated working-tree changes. Do not stage them.

## Verification and commits

- For Swift changes: run the focused affected tests, a simulator build, and `git diff --check`.
- Review the final diff for sync regressions, actor isolation, accidental secrets, and UI-state correctness.
- When a self-contained task passes its required checks, commit only its files with a concise imperative message. Do not commit if unrelated changes obscure ownership; report that blocker instead.

## Key commands

- Use the Build iOS Apps plugin and its XcodeBuildMCP tools for every iOS build, test, run, simulator, or UI-debugging pass; do not substitute raw `xcodebuild` when those tools are available.
- Build/test through XcodeBuildMCP with project `iWatch.xcodeproj`, scheme `iWatch`.
- Sync changes require `-only-testing:iWatchTests` at minimum.
