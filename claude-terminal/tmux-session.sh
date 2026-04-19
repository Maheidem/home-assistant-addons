#!/bin/bash
# Initial command run inside the tmux session created by run.sh.
#
# This script runs ONCE per tmux session lifetime (when tmux's `new-session -A`
# creates a fresh session). When the user reattaches to an existing session,
# tmux skips this script and shows whatever the session was already running.
#
# Behavior:
#   - If $STARTUP_CMD is set, run it via login bash. When it exits (crash, /exit,
#     update), fall through to an interactive bash so the user can recover.
#   - If $STARTUP_CMD is empty, just start an interactive bash.
#
# Passing the command via env var (rather than shell-interpolating it into the
# tmux command line) avoids quoting hell when the command contains quotes,
# spaces, or shell metacharacters.

set -u

if [ -n "${STARTUP_CMD:-}" ]; then
    bash -lc "${STARTUP_CMD}" || true
    echo
    echo "[claude-terminal] startup command exited; dropping to bash. Re-run it manually if you want."
    echo
fi

exec bash -l
