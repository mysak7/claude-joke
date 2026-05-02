#!/usr/bin/env bash
# Sets up cron jobs based on times defined in config.json.
# Re-running this script overwrites any previously created entries.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/config-joke.json"
RUN_SCRIPT="$SCRIPT_DIR/run-joke.sh"
MARKER="# claude-joke-cron"

if [[ ! -f "$CONFIG" ]]; then
    echo "Error: config-joke.json not found at $CONFIG" >&2
    exit 1
fi

# Parse times array from config
mapfile -t TIMES < <(python3 -c "
import json, sys
cfg = json.load(open('$CONFIG'))
times = cfg.get('times', [])
if not times:
    print('Error: no times defined in config-joke.json', file=sys.stderr)
    sys.exit(1)
for t in times:
    print(t)
")

# Build a temp crontab: keep existing non-joke lines, then append new joke lines
TMPFILE=$(mktemp)
trap "rm -f '$TMPFILE'" EXIT

# Strip any previously created entries
crontab -l 2>/dev/null | grep -v "$MARKER" > "$TMPFILE" || true

# Append one cron entry per time
for TIME in "${TIMES[@]}"; do
    HOUR=$(echo "$TIME" | cut -d: -f1)
    MINUTE=$(echo "$TIME" | cut -d: -f2)
    # Remove leading zeros (cron treats 08 as octal in some shells)
    HOUR=$(( 10#$HOUR ))
    MINUTE=$(( 10#$MINUTE ))
    echo "$MINUTE $HOUR * * * \"$RUN_SCRIPT\" $MARKER"
done >> "$TMPFILE"

crontab "$TMPFILE"

echo "Cron jobs installed:"
grep "$MARKER" "$TMPFILE"
