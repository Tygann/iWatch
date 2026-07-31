# Development workflow

1. Check `git status`; preserve unrelated work.
2. Read `AGENTS.md` and the relevant contract under `Docs/`.
3. Make the smallest complete change and add a regression test when behavior changes.
4. Run focused tests, a simulator build, and `git diff --check`.
5. Review the diff, check that no credentials or `xcuserdata` files are staged, then commit the self-contained work.

GitHub Actions runs the same baseline checks for pushes and pull requests. Before an App Store build, use `Docs/CLOUDKIT_RELEASE_CHECKLIST.md` for the live CloudKit verification that CI cannot perform.

Use `Docs/DEVELOPMENT_LOG.md` for durable implementation notes and `Docs/NEXT_STEPS.md` for explicitly deferred work.
