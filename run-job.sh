#!/usr/bin/env bash
# Reads prompt from job.md and runs Claude Code headlessly.
# On success, archives job.md and result to archive/ with a datetime tag.
# On failure, leaves job.md in place so the next run retries.
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

RESULT=$(cd "$WORK_DIR" && /home/mi/.local/bin/claude -p "$PROMPT")

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
