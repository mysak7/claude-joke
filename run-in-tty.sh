#!/usr/bin/env bash
# Runs a prompt through Claude Code in a REAL interactive session inside a tmux
# pane (a genuine PTY), instead of `claude -p`.
#
# Why: `claude -p` is headless and does not open/refresh a usage window the way
# an interactive session does, so it cannot be used to pre-warm a window.
# A tmux pane is an actual terminal, so `claude` starts its normal TUI.
#
# The prompt is handed over as argv (`claude "<prompt>"`), which the TUI submits
# immediately -- far more reliable than simulating keystrokes into the input box.
#
# Completion is detected by a marker file that the prompt itself is told to
# touch as its last action. That is independent of how the TUI renders.
#
# Usage:  run-in-tty.sh "<prompt>"
#         echo "<prompt>" | run-in-tty.sh
#
# Env:
#   TTY_MODEL           model to pass to claude          (default: haiku)
#   TTY_TIMEOUT         seconds to wait for completion   (default: 900)
#   TTY_WORKDIR         working directory for the run    (default: script dir)
#   TTY_CLAUDE          claude binary                    (default: /home/mi/.local/bin/claude)
#   TTY_KEEP            1 = leave the tmux session alive so you can attach
#
# Exit codes:
#   0  finished (marker written)
#   2  usage limit hit
#   3  timed out
#   4  the claude process died without finishing
#
# The transcript of the pane is printed on stdout.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MODEL="${TTY_MODEL:-haiku}"
TIMEOUT="${TTY_TIMEOUT:-900}"
WORKDIR="${TTY_WORKDIR:-$SCRIPT_DIR}"
CLAUDE="${TTY_CLAUDE:-/home/mi/.local/bin/claude}"
KEEP="${TTY_KEEP:-0}"

if [[ $# -ge 1 ]]; then
    PROMPT="$1"
else
    PROMPT=$(cat)
fi

if [[ -z "${PROMPT// }" ]]; then
    echo "run-in-tty.sh: empty prompt" >&2
    exit 64
fi

command -v tmux >/dev/null || { echo "run-in-tty.sh: tmux is required" >&2; exit 64; }
[[ -x "$CLAUDE" ]] || { echo "run-in-tty.sh: claude not found at $CLAUDE" >&2; exit 64; }

RUN_ID="$(date +%Y%m%d-%H%M%S)-$$"
SESSION="claude-tty-$RUN_ID"
STATE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/claude-tty-XXXXXX")
MARKER="$STATE_DIR/done"
PANE_LOG="$STATE_DIR/pane.log"

cleanup() {
    if [[ "$KEEP" != "1" ]]; then
        tmux kill-session -t "$SESSION" 2>/dev/null
        rm -rf "$STATE_DIR"
    else
        echo "run-in-tty.sh: session kept -- tmux attach -t $SESSION (state: $STATE_DIR)" >&2
    fi
}
trap cleanup EXIT

# The marker instruction is appended here rather than kept in the caller's
# prompt, so callers stay free to describe only the actual work.
FULL_PROMPT="$PROMPT

When you have completely finished the task above, run this command as your very last action: touch $MARKER"

# A login-ish shell keeps PATH etc. the same as an interactive terminal, which
# matters under cron where the environment is otherwise nearly empty.
tmux new-session -d -s "$SESSION" -x 200 -y 50 -c "$WORKDIR" \
    "exec $(printf '%q' "$CLAUDE") --model $(printf '%q' "$MODEL") $(printf '%q' "$FULL_PROMPT")" \
    || { echo "run-in-tty.sh: failed to start tmux session" >&2; exit 64; }

capture() {
    # -S - grabs scrollback too; falls back to the visible screen when the TUI
    # runs on the alternate screen (tui: fullscreen), which has no history.
    tmux capture-pane -p -S - -t "$SESSION" 2>/dev/null
}

STATUS=3
DEADLINE=$(( $(date +%s) + TIMEOUT ))

while true; do
    if [[ -f "$MARKER" ]]; then
        STATUS=0
        break
    fi

    if ! tmux has-session -t "$SESSION" 2>/dev/null; then
        # Pane is gone; the last capture we took is all we have.
        STATUS=4
        break
    fi

    capture > "$PANE_LOG"

    if grep -qiE "hit your (monthly|weekly|usage) .*limit|usage limit reached|session limit resets" "$PANE_LOG"; then
        STATUS=2
        break
    fi

    if (( $(date +%s) >= DEADLINE )); then
        STATUS=3
        break
    fi

    sleep 5
done

# One final capture so the transcript reflects the end state.
if tmux has-session -t "$SESSION" 2>/dev/null; then
    capture > "$PANE_LOG"
fi

# Ask the TUI to shut down cleanly before the trap kills the session.
if tmux has-session -t "$SESSION" 2>/dev/null; then
    tmux send-keys -t "$SESSION" -l "/exit" 2>/dev/null
    tmux send-keys -t "$SESSION" Enter 2>/dev/null
    for _ in $(seq 1 10); do
        tmux has-session -t "$SESSION" 2>/dev/null || break
        sleep 1
    done
fi

# The pane is padded out to its full height, so squeeze the runs of blank lines
# it leaves behind and drop the trailing ones before printing the transcript.
sed -e 's/[[:space:]]*$//' "$PANE_LOG" 2>/dev/null \
    | cat -s \
    | sed -e :a -e '/^$/{$d;N;ba' -e '}'

exit "$STATUS"
