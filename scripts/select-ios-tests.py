#!/usr/bin/env python3
"""Select iWatch simulator verification from the paths in a Git diff."""

import argparse
from dataclasses import dataclass
from pathlib import Path
import re
import subprocess


UI_TARGET = "iWatchUITests"
UI_SOURCE = Path("iWatchUITests/iWatchUITests.swift")
SELECTOR_FILES = {".github/workflows/ios.yml", "scripts/select-ios-tests.py", "scripts/test-ios-test-selection.py"}
SETTINGS_COMPONENTS = "iWatch/DesignSystem/SettingsComponents.swift"
SETTINGS_SMOKE = (
    f"{UI_TARGET}/{UI_TARGET}/testNotificationSettingsAtStandardTextSize",
    f"{UI_TARGET}/{UI_TARGET}/testNotificationSettingsAtAccessibilityTextSize",
)
SETTINGS_AVATAR = f"{UI_TARGET}/AccountAvatarUITests/testAdjustApplyAndRemovePhotoAtStandardAndAccessibilityTextSizes"

# Match only literal styles on SettingsRowIcon. Keep identifiers, calls, and
# accessibility semantics intact when comparing the two source revisions.
ICON_STYLES = (
    r"            \.font\(\.system\(size: [0-9.]+, weight: \.(?:regular|medium|semibold|bold)\)\)",
    r"            \.foregroundStyle\(\.(?:white|black)\)",
    r"            \.frame\(width: [0-9.]+, height: [0-9.]+\)",
    r"            \.background\(tint\.gradient, in: RoundedRectangle\(cornerRadius: [0-9.]+\)\)",
)
UI_GROUPS = (
    (
        (
            "iWatch/Features/Settings/",
            "iWatch/Platform/Notifications/",
            SETTINGS_COMPONENTS,
        ),
        (
            "testSettingsNavigation", "testStartPage", "testNotificationSettings",
            "testSync", "testTrakt", "testGuestAccount", "testSignedInAccount",
            "testSupport", "testReferenceGallery", "testAbout",
        ),
    ),
    (
        ("iWatch/Features/Library/",),
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


@dataclass(frozen=True)
class Selection:
    unit: bool = False
    ui: tuple[str, ...] = ()

    @property
    def simulator(self):
        return self.unit or bool(self.ui)


def normalize_icon_styles(source):
    lines = source.splitlines(keepends=True)
    try:
        start = lines.index("struct SettingsRowIcon: View {\n")
        end = lines.index("}\n", start)
    except ValueError:
        return source
    for index in range(start + 1, end):
        for pattern in ICON_STYLES:
            if re.fullmatch(pattern + r"\n", lines[index]):
                lines[index] = pattern
                break
    return "".join(lines)


def cosmetic_icon_change(base, head):
    versions = [
        subprocess.run(
            ["git", "show", f"{ref}:{SETTINGS_COMPONENTS}"],
            capture_output=True, text=True, check=False,
        )
        for ref in (base, head)
    ]
    if any(version.returncode for version in versions):
        return False
    before, after = (version.stdout for version in versions)
    return before != after and normalize_icon_styles(before) == normalize_icon_styles(after)


def documentation(path):
    return path == "AGENTS.md" or path.startswith("Docs/") and path.endswith(".md")


def select(paths, full_ui=False, cosmetic_icon=False):
    if full_ui:
        return Selection(True, (UI_TARGET,))

    unit = False
    ui = set()
    prefixes = set()
    for path in paths:
        if documentation(path):
            continue
        if path in SELECTOR_FILES or (path == SETTINGS_COMPONENTS and cosmetic_icon):
            ui.update(SETTINGS_SMOKE)
            continue
        unit = True
        if path.startswith("iWatchTests/"):
            continue
        for roots, tests in UI_GROUPS:
            if any(path == root or (root.endswith("/") and path.startswith(root)) for root in roots):
                prefixes.update(tests)
                if SETTINGS_COMPONENTS in roots:
                    ui.add(SETTINGS_AVATAR)
                break
        else:
            return Selection(True, (UI_TARGET,))

    if prefixes:
        methods = set(re.findall(r"^    func (test\w+)\(", UI_SOURCE.read_text(), re.MULTILINE))
        unmatched = sorted(prefix for prefix in prefixes if not any(m.startswith(prefix) for m in methods))
        if unmatched:
            raise SystemExit("UI test prefixes without matches: " + ", ".join(unmatched))
        ui.update(f"{UI_TARGET}/{UI_TARGET}/{name}" for name in methods if name.startswith(tuple(prefixes)))
    return Selection(unit, tuple(sorted(ui)))


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
    cosmetic_icon = SETTINGS_COMPONENTS in paths and cosmetic_icon_change(args.base, args.head)
    selection = select(paths, args.full_ui, cosmetic_icon)
    with args.outputs.open("a") as outputs:
        outputs.write(f"simulator={str(selection.simulator).lower()}\n")
        outputs.write(f"unit-tests={str(selection.unit).lower()}\n")
        outputs.write("ui-selection=" + " ".join(selection.ui) + "\n")
    print("Simulator verification:", "enabled" if selection.simulator else "skipped")
    print("Unit tests:", "full suite" if selection.unit else "skipped")
    print("UI selection:", ", ".join(selection.ui) or "none")


if __name__ == "__main__":
    main()
