#!/usr/bin/env bash
# Reads prompt from config.json and runs Claude Code headlessly in this directory.
# Called by cron jobs set up via setup-cron.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/config-joke.json"
LOG="$SCRIPT_DIR/jokes.log"

PROMPT=$(python3 -c "import json; print(json.load(open('$CONFIG'))['prompt'])")

cd "$SCRIPT_DIR"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Running joke prompt..." >> "$LOG"
/home/mi/.local/bin/claude -p "$PROMPT" >> "$LOG" 2>&1
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Done." >> "$LOG"
