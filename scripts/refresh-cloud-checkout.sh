#!/usr/bin/env bash
set -euo pipefail

repo=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
git -C "$repo" fetch --no-tags origin +refs/heads/main:refs/remotes/origin/main
target=$(git -C "$repo" rev-parse --verify refs/remotes/origin/main^{commit})
head=$(git -C "$repo" rev-parse --verify HEAD)
status=$(git -C "$repo" status --porcelain=v1 --untracked-files=all)

if [ -z "$status" ]; then
    if [ "$head" = "$target" ]; then
        printf '%s\n' "$repo"
        exit 0
    fi
    if git -C "$repo" merge-base --is-ancestor "$head" "$target" &&
       git -C "$repo" merge --ff-only --no-overwrite-ignore "$target" >&2; then
        printf '%s\n' "$repo"
        exit 0
    fi
fi

# A separate worktree keeps local edits and unpublished commits available.
fresh=$(mktemp -d "${TMPDIR:-/tmp}/iwatch-main.XXXXXX")
if ! git -C "$repo" worktree add --detach -- "$fresh" "$target" >&2; then
    rmdir "$fresh" 2>/dev/null || true
    exit 1
fi
printf '%s\n' "$fresh"
