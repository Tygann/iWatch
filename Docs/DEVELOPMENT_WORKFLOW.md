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

For app and test changes, the `xcode-27` runner uses Xcode 27.1 and an iPhone 17 simulator running iOS 27.2. It builds the app and test bundles once, then runs the full `iWatchTests` suite and the selected `iWatchUITests` cases without rebuilding. The selector in `scripts/select-ios-tests.py` groups existing UI tests by settings, library, and browse/detail. Shared code, project configuration, workflow changes, and unmapped app areas get the full UI suite. Unit-test-only changes run the unit suite. The workflow uploads available result bundles, including UI attachments, on failure.

The full UI suite runs weekly. To run it on demand, open **Actions → iOS verification → Run workflow** and select the branch or ref you want to verify.

## Release handoff

Run the full UI workflow for the revision you plan to release and check the result before distribution. Use `Docs/CLOUDKIT_RELEASE_CHECKLIST.md` for live CloudKit checks. Xcode Cloud handles archives, signing, and TestFlight or App Store distribution under its App Store Connect workflow settings. Keep distribution cadence and production credentials there. Simulator jobs use test configuration and require no production credentials.

Use `Docs/DEVELOPMENT_LOG.md` for durable implementation notes and `Docs/NEXT_STEPS.md` for explicitly deferred work.
