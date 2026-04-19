#!/usr/bin/with-contenv bashio
# Claude Terminal — boot script.
#
# Responsibilities:
#   1. Ensure persistent storage exists at /config/claude-config
#   2. Seed a default settings.json on first boot (USE_BUILTIN_RIPGREP, DISABLE_AUTOUPDATER)
#   3. Read the user's optional `startup_command` add-on option
#   4. Launch ttyd → tmux. tmux's `-A` flag attaches to an existing session if there is one,
#      so closing the browser leaves the session running and reopening reattaches.
#
# All Claude Code state (auth, MCP config, plugins, conversation history, channels)
# lives under $CLAUDE_CONFIG_DIR which points at the persistent /config volume,
# so it survives container restarts and add-on updates.

set -euo pipefail

CLAUDE_DIR=/config/claude-config
DEFAULT_SETTINGS=/opt/claude-defaults/settings.json

# --- Persistent storage ----------------------------------------------------
mkdir -p "${CLAUDE_DIR}"
chmod 700 "${CLAUDE_DIR}"

if [ ! -f "${CLAUDE_DIR}/settings.json" ]; then
    cp "${DEFAULT_SETTINGS}" "${CLAUDE_DIR}/settings.json"
    bashio::log.info "Seeded default settings.json (USE_BUILTIN_RIPGREP=0, DISABLE_AUTOUPDATER=1)"
fi

# --- Persist auxiliary user state -----------------------------------------
# CLAUDE_CONFIG_DIR covers everything Claude Code writes. The four directories
# below are NOT under Claude's control but are still "config the user set up"
# (SSH keys for git push, gitconfig identity, GitHub CLI auth, shell history).
# Symlink them into the persistent volume so they survive container restarts
# and add-on updates.
ensure_symlink() {
    local src="$1" target="$2"
    rm -rf "${src}" 2>/dev/null || true
    ln -sf "${target}" "${src}"
}
mkdir -p "${CLAUDE_DIR}/ssh" "${CLAUDE_DIR}/config-gh" /root/.config
chmod 700 "${CLAUDE_DIR}/ssh"
touch "${CLAUDE_DIR}/gitconfig" "${CLAUDE_DIR}/bash_history"
ensure_symlink /root/.ssh          "${CLAUDE_DIR}/ssh"
ensure_symlink /root/.gitconfig    "${CLAUDE_DIR}/gitconfig"
ensure_symlink /root/.config/gh    "${CLAUDE_DIR}/config-gh"
ensure_symlink /root/.bash_history "${CLAUDE_DIR}/bash_history"
# Tighten any keys the user has dropped into the persistent SSH dir.
if [ -d "${CLAUDE_DIR}/ssh" ]; then
    find "${CLAUDE_DIR}/ssh" -type f -exec chmod 600 {} \;
fi

# --- Environment -----------------------------------------------------------
# CLAUDE_CONFIG_DIR is the official knob for relocating Claude Code state.
# Setting it here propagates through ttyd → bash → tmux → claude.
export CLAUDE_CONFIG_DIR="${CLAUDE_DIR}"
export HOME=/root

# --- Optional startup command ---------------------------------------------
# Read once from the add-on options and export so the tmux wrapper script can read it.
# Empty string (default) → plain bash. Otherwise → run the command then drop to bash.
# Primary: bashio::config (queries the HA supervisor API).
# Fallback: /data/options.json (always mounted by HA on boot, and the only
# source available in local docker testing where the supervisor isn't reachable).
STARTUP_CMD=$(bashio::config 'startup_command' '' 2>/dev/null || echo '')
if [ -z "${STARTUP_CMD}" ] && [ -f /data/options.json ]; then
    STARTUP_CMD=$(jq -r '.startup_command // ""' /data/options.json 2>/dev/null || echo '')
fi
export STARTUP_CMD

if [ -n "${STARTUP_CMD}" ]; then
    bashio::log.info "Startup command: ${STARTUP_CMD}"
else
    bashio::log.info "No startup command configured; tmux will launch a plain bash shell"
fi

# --- Welcome banner --------------------------------------------------------
# Written every boot (idempotent). Shown by interactive bash sessions on login.
cat > /etc/profile.d/01-claude-terminal-welcome.sh <<'EOF'
if [[ $- == *i* ]] && [ -z "${CLAUDE_TERMINAL_WELCOMED:-}" ]; then
    export CLAUDE_TERMINAL_WELCOMED=1
    cat <<'BANNER'

  Claude Terminal
  ───────────────
  Type `claude` to start Claude Code (you'll be prompted to log in on first run).
  Closing the browser keeps your session alive — reopen to reattach.
  Plugins, MCPs, skills you install persist under /config/claude-config/.
  Set the `startup_command` add-on option to auto-launch on boot
  (e.g. `claude -c --channels plugin:telegram@claude-plugins-official`).

BANNER
fi
EOF

# --- Start tmux session at container boot ---------------------------------
# This runs STARTUP_CMD at boot, BEFORE any browser is attached, so
# always-on commands (e.g. `claude -c --channels plugin:telegram@...`) start
# immediately and stay running even if the user never opens the web terminal.
# `-d` creates the session detached. ttyd attaches to it later.
if ! tmux has-session -t claude-main 2>/dev/null; then
    tmux new-session -d -s claude-main -c /config /opt/tmux-session.sh
    bashio::log.info "Started detached tmux session 'claude-main'"
fi

# --- Launch web terminal ---------------------------------------------------
# ttyd attaches to the existing tmux session on each browser connect.
# `new-session -A` is create-or-attach: if the session died (rare; e.g. user
# typed `exit` after STARTUP_CMD finished and tmux became empty), a fresh one
# is created so the web terminal still works.
bashio::log.info "Starting ttyd on port 7681"
# ttyd client options (passed through to xterm.js):
#   copyOnSelect=true → highlight text → auto-copies to clipboard (no Ctrl+C)
#   cursorBlink=true  → visible cursor blink
#   fontSize=14       → slightly larger than default 12px for readability
#   scrollback=5000   → xterm.js scrollback lines (separate from tmux history)
# Intentionally NOT setting fontFamily: xterm.js's default monospace stack
# (courier new / courier / monospace) renders correctly; custom values with
# commas / quoted family names broke letter spacing in practice.
exec ttyd \
    --port 7681 \
    --interface 0.0.0.0 \
    --writable \
    --ping-interval 30 \
    --max-clients 1 \
    --client-option 'copyOnSelect=true' \
    --client-option 'cursorBlink=true' \
    --client-option 'fontSize=14' \
    --client-option 'scrollback=5000' \
    bash -lc 'tmux new-session -A -s claude-main -c /config /opt/tmux-session.sh'
