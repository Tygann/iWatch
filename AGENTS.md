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

## TestFlight and App Store release notes

- Treat `Docs/releases/ReleaseHistory.md` as the canonical record of uploaded builds and the source of truth for the newest published-build boundary.
- When asked for notes for an uploaded build, first identify the newest logged release and review only meaningful product changes after its recorded source commit. Ignore release-history-only commits and do not repeat work already described by the previous build.
- For the first logged build, summarize the current tester-visible product and record the uploaded source commit as the initial boundary.
- Write concise, user-facing notes rather than commit summaries. For TestFlight, describe the important new behavior and improvements, then include two to four focused requests under `Please test`. For App Store releases, omit tester instructions and debugging or implementation language.
- Return the exact pasteable App Store Connect copy in a fenced plain-text code block.
- Prepend the finalized entry to `Docs/releases/ReleaseHistory.md`. Record the version, build, upload date, channel, and full uploaded source commit so the next release can compare against it.
- Release-history-only edits require `git diff --check` and a final diff review, not an app build. Preserve unrelated work, stage only the release-history and directly related instruction files, and commit the self-contained documentation change.

## Key commands

- Use the Build iOS Apps plugin and its XcodeBuildMCP tools for every iOS build, test, run, simulator, or UI-debugging pass; do not substitute raw `xcodebuild` when those tools are available.
- Build/test through XcodeBuildMCP with project `iWatch.xcodeproj`, scheme `iWatch`.
- Sync changes require `-only-testing:iWatchTests` at minimum.
