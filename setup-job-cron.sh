#!/usr/bin/env bash
# Installs a cron entry at 14:00 to run run-job.sh.
# Re-running this script overwrites any previously created entry.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_SCRIPT="$SCRIPT_DIR/run-job.sh"
MARKER="# claude-job-cron"

TMPFILE=$(mktemp)
trap "rm -f '$TMPFILE'" EXIT

crontab -l 2>/dev/null | grep -v "$MARKER" > "$TMPFILE" || true

echo "0 14 * * * \"$RUN_SCRIPT\" $MARKER" >> "$TMPFILE"

crontab "$TMPFILE"

echo "Cron job installed:"
grep "$MARKER" "$TMPFILE"
