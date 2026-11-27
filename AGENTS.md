# iWatch agent guidance

## Cloud startup and delivery

- Before editing in Codex Cloud, run `scripts/refresh-cloud-checkout.sh` with network access and use the path it prints. Re-read `AGENTS.md` from that checkout. If the helper is absent, fetch `origin/main` and use a clean checkout at that revision. If shell Git cannot fetch, use the GitHub connector to verify the current base. Preserve any existing local changes and report a failed refresh.
- When iOS verification is required and the workspace lacks Xcode, publish a scoped commit to a task branch and open a draft PR to run the repository’s macOS GitHub Actions workflow. Use the GitHub connector when shell Git publishing is unavailable. Monitor CI to completion and land the verified change when authorized. Honor any explicit instruction to keep work local. Report the specific blocker if publishing or CI cannot proceed.
- After landing changes on `main`, run the refresh helper again and verify that the active checkout uses the landed revision.

## Scope and architecture

- iWatch is a local-first SwiftUI app. SwiftData/CloudKit owns cross-device library replication; Trakt is an optional external account sync.
- Keep SwiftUI views thin. Put library mutations in `LibraryRepository`, remote sync orchestration in `SyncEngine`, and provider HTTP details in `Data/Remote`.
- Treat the Trakt account key as a hard sync boundary. Never send one account's outbox rows to another account.

## Product design

- Design every user-facing change to follow the current Apple Human Interface Guidelines and platform-native iOS behavior.
- Prefer standard SwiftUI controls, navigation, feedback, and accessibility behavior over custom equivalents unless a custom interaction clearly improves the experience.
- Prioritize clarity, progressive disclosure, Dynamic Type, VoiceOver, adequate touch targets, and system appearance support.
- Keep settings focused on meaningful user choices. Place diagnostics, developer configuration, and destructive maintenance actions in clearly labeled secondary flows.
- Verify meaningful UI changes on Simulator at standard and accessibility text sizes where the affected flow supports them. Complete required simulator verification before landing.

## Safety

- Never print, commit, or modify live credentials. `iWatch/Secrets.plist` is local-only; use `Secrets.example.plist` as its public template.
- Do not delete or reset a SwiftData/CloudKit store as automatic error recovery.
- Preserve unrelated working-tree changes. Do not stage them.

## Verification and commits

- Run `git diff --check` and applicable architecture, Trakt configuration, and CloudKit schema checks. Use the [CI test selection rules](Docs/DEVELOPMENT_WORKFLOW.md#github-actions-verification) for simulator verification. Run the affected UI flows and full `iWatchTests` suite for behavior changes. For allowlisted cosmetic changes, run the affected simulator smoke tests at standard and accessibility text sizes. For selector-only changes, verify the routing on Linux and run the simulator smoke pair.
- Review the final diff for sync regressions, actor isolation, accidental secrets, and UI-state correctness.
- Automatically commit and push completed, self-contained changes when verification supports shipping them. Use a direct push to `main` for small changes when the remote base is current, the completed checks cover the change, and repository rules allow it. Honor explicit instructions to keep changes local.
- Require green macOS CI on a PR before landing persistence or schema migrations, CloudKit or Trakt sync, authentication, and CI or release workflow changes. Use a draft PR whenever required simulator checks cannot run before publishing the change. Monitor CI through completion, investigate failures, and report any unverified checks.
- Run the full UI suite before releasing and use the weekly run to catch cross-flow regressions. Keep simulator checks on fixtures or test configuration. Keep signing credentials and production keys in the release environment.
- See `Docs/DEVELOPMENT_WORKFLOW.md` for cloud verification, test selection, and release handoff.

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
