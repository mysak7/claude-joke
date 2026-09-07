#!/usr/bin/env bash
# Reads prompt from config-joke.json and runs it through a real interactive
# Claude Code session (see run-in-tty.sh). Called by cron via setup-joke-cron.sh.
#
# A run also opens a fresh usage window ("pre-warming"). `claude -p` turned out
# not to do that -- headless runs do not behave like interactive ones -- so the
# prompt now goes through an actual terminal instead.
#
# Pre-warming only works once the previous window has expired: while an
# exhausted window is still running the run is refused, so on a limit refusal we
# retry until the old window dies instead of giving up.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/config-joke.json"
LOG="$SCRIPT_DIR/jokes.log"
RUNNER="$SCRIPT_DIR/run-in-tty.sh"

cfg() { python3 -c "import json,sys; print(json.load(open('$CONFIG')).get('$1', '$2'))"; }

PROMPT=$(python3 -c "import json; print(json.load(open('$CONFIG'))['prompt'])")
MODEL=$(cfg model haiku)
RETRY_MIN=$(cfg retry_every_minutes 10)
RETRY_FOR_MIN=$(cfg retry_for_minutes 180)
RUN_TIMEOUT=$(cfg run_timeout_seconds 900)

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

cd "$SCRIPT_DIR"
DEADLINE=$(( $(date +%s) + RETRY_FOR_MIN * 60 ))
ATTEMPT=1

while true; do
    log "Running joke prompt in a tty (model: $MODEL, attempt $ATTEMPT)..."

    set +e
    OUTPUT=$(TTY_MODEL="$MODEL" TTY_TIMEOUT="$RUN_TIMEOUT" TTY_WORKDIR="$SCRIPT_DIR" \
        "$RUNNER" "$PROMPT" 2>&1)
    RC=$?
    set -e

    printf '%s\n' "$OUTPUT" >> "$LOG"

    case "$RC" in
        0)
            log "Done."
            exit 0
            ;;
        2)
            if (( $(date +%s) + RETRY_MIN * 60 >= DEADLINE )); then
                log "Still limited after ${RETRY_FOR_MIN}m. Giving up until next cron slot."
                exit 1
            fi
            log "Usage limit hit -- window still busy. Retrying in ${RETRY_MIN}m."
            sleep $(( RETRY_MIN * 60 ))
            ATTEMPT=$(( ATTEMPT + 1 ))
            ;;
        3)
            log "Timed out after ${RUN_TIMEOUT}s. Giving up."
            exit 1
            ;;
        *)
            log "Failed (exit $RC). Giving up."
            exit 1
            ;;
    esac
done
