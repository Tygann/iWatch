#!/usr/bin/env python3
"""Select iWatch simulator verification from the paths in a Git diff."""

import argparse
from pathlib import Path
import re
import subprocess


UI_TARGET = "iWatchUITests"
UI_SOURCE = Path("iWatchUITests/iWatchUITests.swift")
WORKFLOW_FILES = (".github/workflows/ios.yml", "scripts/select-ios-tests.py")
APP_PATHS = ("iWatch/", "iWatch.xcodeproj/", "iWatchTests/", "iWatchUITests/")
UI_GROUPS = (
    (
        (
            "iWatch/Features/Settings/",
            "iWatch/Platform/Notifications/",
            "iWatch/DesignSystem/SettingsComponents.swift",
        ),
        (
            "testSettingsNavigation", "testStartPage", "testNotificationSettings",
            "testSync", "testTrakt", "testGuestAccount", "testSignedInAccount",
            "testSupport", "testReferenceGallery", "testAbout",
        ),
    ),
    (
        ("iWatch/Features/Library/", "iWatch/Data/Local/", "iWatch/Data/Repositories/"),
        (
            "testQuickWatch", "testContinueWatching", "testSavedShows", "testColdLaunch",
            "testShowCollection", "testWatchlist", "testRetainedLibraryError", "testLibraryStartupRecovery",
        ),
    ),
    (
        ("iWatch/Features/Browse/", "iWatch/Features/MediaDetail/"),
        (
            "testLaunchTabs", "testQuickWatch", "testCachedSeason", "testSeasonRetry",
            "testWatchlist",
        ),
    ),
)


def select(paths, full_ui):
    if full_ui or any(path in WORKFLOW_FILES for path in paths):
        return True, [UI_TARGET]

    app_paths = [path for path in paths if path.startswith(APP_PATHS)]
    prefixes = set()
    for path in app_paths:
        if path.startswith("iWatchTests/"):
            continue
        for roots, tests in UI_GROUPS:
            if any(path == root or (root.endswith("/") and path.startswith(root)) for root in roots):
                prefixes.update(tests)
                break
        else:
            # Shared code, project configuration, and unmapped app areas can affect any flow.
            return True, [UI_TARGET]

    if not prefixes:
        return bool(app_paths), []

    methods = set(re.findall(r"^    func (test\w+)\(", UI_SOURCE.read_text(), re.MULTILINE))
    unmatched = sorted(prefix for prefix in prefixes if not any(m.startswith(prefix) for m in methods))
    if unmatched:
        raise SystemExit("UI test prefixes without matches: " + ", ".join(unmatched))
    return True, [f"{UI_TARGET}/{UI_TARGET}/{name}" for name in sorted(methods) if name.startswith(tuple(prefixes))]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("base")
    parser.add_argument("head")
    parser.add_argument("--full-ui", action="store_true")
    parser.add_argument("--outputs", required=True, type=Path)
    args = parser.parse_args()

    changed = subprocess.check_output(
        ["git", "diff", "--name-only", "--no-renames", "-z", args.base, args.head, "--"]
    )
    paths = [path.decode(errors="surrogateescape") for path in changed.split(b"\0") if path]
    run_unit, ui_tests = select(paths, args.full_ui)
    with args.outputs.open("a") as outputs:
        outputs.write(f"simulator={str(run_unit).lower()}\n")
        outputs.write("ui-selection=" + " ".join(ui_tests) + "\n")
    print("Simulator verification:", "enabled" if run_unit else "skipped")
    print("UI selection:", ", ".join(ui_tests) or "none")


if __name__ == "__main__":
    main()
