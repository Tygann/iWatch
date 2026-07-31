# iWatch agent guidance

## Scope and architecture

- iWatch is a local-first SwiftUI app. SwiftData/CloudKit owns cross-device library replication; Trakt is an optional external account sync.
- Keep SwiftUI views thin. Put library mutations in `LibraryRepository`, remote sync orchestration in `SyncEngine`, and provider HTTP details in `Data/Remote`.
- Treat the Trakt account key as a hard sync boundary. Never send one account's outbox rows to another account.

## Product design

- Design every user-facing change to follow the current Apple Human Interface Guidelines and platform-native iOS behavior.
- Prefer standard SwiftUI controls, navigation, feedback, and accessibility behavior over custom equivalents unless a custom interaction clearly improves the experience.
- Prioritize clarity, progressive disclosure, Dynamic Type, VoiceOver, adequate touch targets, and system appearance support.
- Keep settings focused on meaningful user choices. Place diagnostics, developer configuration, and destructive maintenance actions in clearly labeled secondary flows.
- Verify meaningful UI changes on Simulator at standard and accessibility text sizes before committing.

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
