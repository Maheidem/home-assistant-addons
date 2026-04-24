#!/bin/bash
# Foreground launcher for `opencode web`.
#
# Kept separate from run.sh so the launch invocation is easy to tweak
# without walking through the whole boot sequence. PID 1 (tini/s6) exec's
# run.sh, which exec's this script, which exec's opencode web — so SIGTERM
# from the HA supervisor propagates cleanly to opencode.
#
# If opencode web exits unexpectedly, drop to an interactive bash so the
# user can inspect state via `podman exec` or `docker attach`. The welcome
# banner (written by run.sh) tells them where to look.

set -u

opencode_args=(
    web
    --hostname 0.0.0.0
    --port 7682
    --log-level "${OPENCODE_LOG_LEVEL:-info}"
)

echo "[opencode-terminal] exec: opencode ${opencode_args[*]}"

if command -v opencode >/dev/null 2>&1; then
    exec opencode "${opencode_args[@]}"
fi

echo "[opencode-terminal] 'opencode' binary not found on PATH. Dropping to bash."
exec bash -l
