# Development workflow

1. Read `AGENTS.md` and the relevant product or architecture notes. Check the GitHub `main` head and working tree. Start from current `main`, using an isolated checkout or applying only the intended patch to a verified GitHub base when the workspace has older or unrelated edits.
2. Make the smallest complete change. Add focused regression coverage when existing tests miss a failure mode. Review the scoped diff and run `git diff --check` and the applicable scripts under `scripts/`.
3. Verify app and test changes on an iPhone simulator. Use XcodeBuildMCP on a Mac for interactive builds and visual checks. From Codex Cloud on Linux, use GitHub Actions for simulator verification and the GitHub connector to publish changes and inspect checks when shell Git is unavailable.
4. Commit and push when the required checks pass. Push directly to `main` for small changes covered by completed checks where repository rules allow it. Use a draft PR to get required macOS results before landing. Watch CI through completion, investigate failures, and report any checks still unverified.

## Refresh a cloud checkout

Run `scripts/refresh-cloud-checkout.sh` at the start of each cloud task and again after the change lands on GitHub `main`. Use the path it prints for subsequent commands. The helper fetches `origin/main` and fast-forwards a clean checkout when safe. If the existing checkout has edits or diverged commits, it creates a temporary detached worktree at the fetched commit and leaves the existing checkout intact. Use `git worktree remove PATH` to clean up a temporary worktree once its work is published and it is clean.

If the seed checkout predates the helper, fetch `origin/main` and create a clean worktree there first. If shell Git still cannot fetch with network access enabled, verify the head through the GitHub connector and use that verified base. A stale checkout can still be useful for recovering earlier local edits.

## GitHub Actions verification

The **iOS verification** workflow runs repository checks on Linux for pushes to `main` and pull requests. Documentation-only changes can finish without acquiring a macOS runner.

The Linux job tests the selector against sample Git diffs and checks the workflow outputs. The selector combines the coverage requested by every changed path.

| Change | Simulator coverage |
| --- | --- |
| Allowlisted cosmetic Settings row icon edits | Notifications Settings navigation at standard and accessibility text sizes |
| Behavior in Settings, notifications, Library, Browse, or Media Detail | Full `iWatchTests` and the mapped UI flows, including avatar editing for Settings |
| Unit test files only | Full `iWatchTests` |
| Selector, routing tests, or iOS verification workflow only | Settings smoke pair |
| Shared app or data code, project configuration, UI test changes, and unmapped paths | Full unit and UI suites |
| `AGENTS.md` and Markdown under `Docs/` only | Linux checks |

CI checks the actual before-and-after source for cosmetic changes. The allowlist covers literal font, foreground, frame, and corner radius values inside `SettingsRowIcon` in `SettingsComponents.swift`. Changes to actions, accessibility semantics, other declarations, or unrecognized edits in that file run the Settings behavior route. Extend the allowlist with focused routing tests when adding a cosmetic route for another screen. Mixed changes keep the union of focused tests and run the full unit suite if any path calls for it. A broad change takes precedence.

The `xcode-27` runner uses Xcode 27.1 and an iPhone 17 simulator running iOS 27.2. It builds the app and test bundles once. Selected test steps reuse that build, and the workflow uploads available result bundles on failure.

The full UI suite runs weekly. To run it on demand, open **Actions → iOS verification → Run workflow** and select the branch or ref you want to verify.

The Actions run summary shows the selected tier, its reason, the test list, and elapsed times for Linux preflight and simulator stages. Simulator stage times include setup. Share the run link when waiting for CI.

## Release handoff

For a user-visible change, add a paste-ready bullet under `TestFlight notes` in the PR description. For a direct push, use that heading in the commit body. Repeat the bullet in the chat summary. When squash-merging, include the PR’s `TestFlight notes` section in the squash commit body and verify it on `main`. Internal-only changes such as CI tuning and test maintenance can omit the section.

```text
TestFlight notes
- Settings now uses colored icons to make options easier to spot.
```

When preparing notes for an uploaded build, review the changes since the last recorded build, consolidate related bullets, and add two to four focused requests under `Please test`. Record the final notes in `Docs/releases/ReleaseHistory.md` with the build number and source commit.

Run the full UI workflow for the revision you plan to release and check the result before distribution. Use `Docs/CLOUDKIT_RELEASE_CHECKLIST.md` for live CloudKit checks. Xcode Cloud handles archives, signing, and TestFlight or App Store distribution under its App Store Connect workflow settings. Keep distribution cadence and production credentials there. Simulator jobs use test configuration and require no production credentials.

Use `Docs/DEVELOPMENT_LOG.md` for durable implementation notes and `Docs/NEXT_STEPS.md` for explicitly deferred work.
