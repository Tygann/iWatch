#!/usr/bin/env python3
"""Check UI architecture boundaries against the repository source on the host."""

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIRECTORIES = ("iWatch/Features", "iWatch/UI")
SOURCE_FILES = ("iWatch/App/ContentView.swift", "iWatch/iWatchApp.swift")
FORBIDDEN = re.compile(
    r"\b(?:TMDbService|TraktService|TMDbClient|TraktClient|"
    r"MediaRecord|MovieRecord|ShowRecord|EpisodeRecord|WatchlistRecord|"
    r"WatchlistItem|WatchedEventRecord|SyncOperationRecord|SyncStateRecord|"
    r"ShowDispositionRecord|LibraryGenerationRecord)\b"
    r"|\b(?:Persistence|ModelContext)\s*\("
    r"|\bFetchDescriptor\s*<"
)


def main() -> int:
    files = [ROOT / path for path in SOURCE_FILES]
    for directory in SOURCE_DIRECTORIES:
        source = ROOT / directory
        if not source.is_dir():
            print(f"Missing UI source directory: {directory}", file=sys.stderr)
            return 1
        swift_files = sorted(source.rglob("*.swift"))
        if not swift_files:
            print(f"No Swift files found in {directory}", file=sys.stderr)
            return 1
        files.extend(swift_files)

    failures = []
    for path in files:
        if not path.is_file():
            print(f"Missing UI source file: {path.relative_to(ROOT)}", file=sys.stderr)
            return 1
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            match = FORBIDDEN.search(line)
            if match:
                failures.append(
                    f"{path.relative_to(ROOT)}:{number}: "
                    f"disallowed UI dependency: {match.group()}"
                )

    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1
    print(f"UI architecture boundaries passed ({len(files)} Swift files).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
