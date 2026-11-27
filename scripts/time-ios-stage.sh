#!/usr/bin/env bash
# Record the elapsed wall time and preserve the command's exit status.
set -eu

stage=$1
shift
SECONDS=0
result=0
"$@" || result=$?
elapsed=$SECONDS
status=passed
if [ "$result" -ne 0 ]; then
    status=failed
fi

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    printf '### %s\n\n**%s** · %d min %02d s\n\n' \
        "$stage" "$status" "$((elapsed / 60))" "$((elapsed % 60))" >> "$GITHUB_STEP_SUMMARY"
fi
exit "$result"
