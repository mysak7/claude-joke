#!/usr/bin/env bash
# Reads prompt from config-joke.json and runs Claude Code headlessly in this directory.
# Called by cron jobs set up via setup-joke-cron.sh.
#
# A run also opens a fresh 5-hour usage window ("pre-warming"). That only works if
# the previous window has already expired -- while an exhausted window is still
# running, claude -p is refused, consumes nothing and opens no window. So on a
# limit refusal we retry until the old window dies instead of giving up.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/config-joke.json"
LOG="$SCRIPT_DIR/jokes.log"

PROMPT=$(python3 -c "import json; print(json.load(open('$CONFIG'))['prompt'])")
MODEL=$(python3 -c "import json; print(json.load(open('$CONFIG')).get('model', 'haiku'))")
RETRY_MIN=$(python3 -c "import json; print(json.load(open('$CONFIG')).get('retry_every_minutes', 10))")
RETRY_FOR_MIN=$(python3 -c "import json; print(json.load(open('$CONFIG')).get('retry_for_minutes', 180))")

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

cd "$SCRIPT_DIR"
DEADLINE=$(( $(date +%s) + RETRY_FOR_MIN * 60 ))
ATTEMPT=1

while true; do
    log "Running joke prompt (model: $MODEL, attempt $ATTEMPT)..."

    if OUTPUT=$(/home/mi/.local/bin/claude -p --model "$MODEL" "$PROMPT" 2>&1); then
        printf '%s\n' "$OUTPUT" >> "$LOG"
        log "Done."
        exit 0
    fi

    printf '%s\n' "$OUTPUT" >> "$LOG"

    # Only a usage-limit refusal is worth retrying; anything else is a real error.
    if ! grep -qiE 'limit|quota' <<<"$OUTPUT"; then
        log "Failed (not a usage limit). Giving up."
        exit 1
    fi

    if (( $(date +%s) + RETRY_MIN * 60 >= DEADLINE )); then
        log "Still limited after ${RETRY_FOR_MIN}m. Giving up until next cron slot."
        exit 1
    fi

    log "Usage limit hit -- window still busy. Retrying in ${RETRY_MIN}m."
    sleep $(( RETRY_MIN * 60 ))
    ATTEMPT=$(( ATTEMPT + 1 ))
done
