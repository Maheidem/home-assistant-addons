#!/bin/bash
# Initial command run inside the tmux session created by run.sh.
#
# This script runs ONCE per tmux session lifetime (when tmux's `new-session -A`
# creates a fresh session). When the user reattaches to an existing session,
# tmux skips this script and shows whatever the session was already running.
#
# Behavior:
#   - Pipe this pane's output into the session log (see below).
#   - If $STARTUP_CMD is empty, just start an interactive bash.
#   - Otherwise run it via login bash and keep it running: when it exits
#     (crash, /exit, update), restart it after a backoff, so an always-on
#     command (e.g. a Telegram channel) recovers on its own.
#
# Restart policy:
#   - backoff starts at 5s and doubles up to 60s while the command keeps
#     exiting quickly; a run of >= 60s counts as healthy and resets it to 5s.
#   - 5 crash-like exits (runs shorter than 60s) within 10 minutes → give up
#     and drop to bash (a persistent crash needs a human, and a tight loop
#     would just spam the session log). Healthy runs don't count towards
#     this and clear it, so a bot that dies every few minutes keeps coming
#     back, which is the always-on premise.
#   - a file named `no-restart` in the Claude config dir disables the restart
#     (useful when you want the command to exit and stay exited).
#   - Ctrl+C during the countdown cancels the restart and gives you a shell.
#
# Passing the command via env var (rather than shell-interpolating it into the
# tmux command line) avoids quoting hell when the command contains quotes,
# spaces, or shell metacharacters.

set -u

CFG_DIR="${CLAUDE_CONFIG_DIR:-/config/claude-config}"
NO_RESTART="${CFG_DIR}/no-restart"
LOG_DIR="${CFG_DIR}/logs"

# Session log: everything this pane prints goes through s6-log (ships with
# the HA base image's s6-overlay), which rotates while the add-on runs: 2 MB
# per file, 3 rotated files kept, current output in logs/current. A plain
# `cat >> file` would grow without bound under an always-on TUI.
# Done here rather than in run.sh so a session recreated by ttyd's
# `new-session -A` (after the first one died) is logged too. `-o` opens a
# pipe only if the pane has none, so `exec /opt/tmux-session.sh` in an
# already-logged pane can't toggle logging off; the pane_pipe check makes
# that explicit. The pipe dies with the pane, and so does its s6-log.
if [ -n "${TMUX_PANE:-}" ] && [ -x /command/s6-log ]; then
    if [ "$(tmux display -p -t "${TMUX_PANE}" '#{pane_pipe}' 2>/dev/null)" != "1" ]; then
        mkdir -p "${LOG_DIR}" 2>/dev/null
        tmux pipe-pane -o -t "${TMUX_PANE}" "exec /command/s6-log -b n3 s2000000 ${LOG_DIR}" \
            || printf '[claude-terminal] could not attach the session log to this pane\n'
    fi
fi

if [ -z "${STARTUP_CMD:-}" ]; then
    exec bash -l
fi

say() {
    printf '\n[claude-terminal %s] %s\n\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

# A trap (not `trap ''`) so this shell survives the Ctrl+C the user sends to
# the foreground command, while the command itself still gets default SIGINT
# handling (trapped-but-not-ignored signals are reset in child processes).
interrupted=0
trap 'interrupted=1' INT

backoff=5
exits=()
while :; do
    started=$(date +%s)
    bash -lc "${STARTUP_CMD}"
    rc=$?
    now=$(date +%s)
    ran=$((now - started))

    if [ -e "${NO_RESTART}" ]; then
        say "startup command exited with code ${rc} after ${ran}s; ${NO_RESTART} exists, not restarting. Dropping to bash."
        break
    fi

    if [ "${ran}" -ge 60 ]; then
        # Healthy run → reset the backoff and forget earlier crashes.
        backoff=5
        exits=()
    else
        # Crash-like exit → sliding window of such exits within the last 600s.
        recent=()
        for t in "${exits[@]}"; do
            [ $((now - t)) -lt 600 ] && recent+=("${t}")
        done
        recent+=("${now}")
        exits=("${recent[@]}")
        if [ "${#exits[@]}" -ge 5 ]; then
            say "startup command crashed 5x in 10 min; giving up, dropping to bash. Remove the cause and run: exec /opt/tmux-session.sh"
            break
        fi
    fi

    # Short run → the backoff grows after this wait (5, 10, 20, 40, 60, ...).
    say "startup command exited with code ${rc} after ${ran}s; restarting in ${backoff}s (Ctrl+C to cancel and get a shell)"
    interrupted=0
    sleep "${backoff}"
    if [ "${interrupted}" -eq 1 ]; then
        say "restart cancelled; dropping to bash. To resume the loop run: exec /opt/tmux-session.sh"
        break
    fi
    if [ "${ran}" -lt 60 ]; then
        backoff=$((backoff * 2))
        [ "${backoff}" -gt 60 ] && backoff=60
    fi
done

exec bash -l
