#!/usr/bin/env bash
# Reads prompt from job.md and runs it through a real interactive Claude Code
# session (see run-in-tty.sh) rather than `claude -p`, which does not open a
# usage window the way interactive use does.
# On success, archives job.md and result to archive/ with a datetime tag.
# On failure, leaves job.md in place so the next run retries.
# Note: the archived result is the terminal transcript of the run, not the bare
# answer text that `-p` used to return.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JOB_FILE="$SCRIPT_DIR/job.md"
ARCHIVE_DIR="$SCRIPT_DIR/archive"

if [[ ! -f "$JOB_FILE" ]]; then
    exit 0
fi

DATETIME=$(date '+%Y-%m-%dT%H:%M')
ARCHIVED_JOB="$ARCHIVE_DIR/job-${DATETIME}.md"
RESULT_FILE="$ARCHIVE_DIR/job-${DATETIME}-result.md"

mkdir -p "$ARCHIVE_DIR"

FIRST_LINE=$(head -n1 "$JOB_FILE")
if [[ "$FIRST_LINE" == working-directory-path=* ]]; then
    WORK_DIR="${FIRST_LINE#working-directory-path=}"
    PROMPT=$(tail -n +2 "$JOB_FILE")
else
    WORK_DIR="$SCRIPT_DIR"
    PROMPT=$(cat "$JOB_FILE")
fi

RESULT=$(TTY_WORKDIR="$WORK_DIR" TTY_MODEL="${JOB_MODEL:-opus}" TTY_TIMEOUT="${JOB_TIMEOUT:-1800}" \
    "$SCRIPT_DIR/run-in-tty.sh" "$PROMPT")

{
    echo "# Job result"
    echo ""
    echo "**Run at:** ${DATETIME}"
    echo "**Source:** job-${DATETIME}.md"
    echo ""
    echo "---"
    echo ""
    echo "$RESULT"
} > "$RESULT_FILE"

cp "$JOB_FILE" "$ARCHIVED_JOB"
rm "$JOB_FILE"
