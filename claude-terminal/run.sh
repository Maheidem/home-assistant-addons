#!/usr/bin/with-contenv bashio
# Claude Terminal — boot script.
#
# Responsibilities, in order:
#   1. Ensure persistent storage exists at /config/claude-config
#   2. Seed defaults on first boot (settings.json, /config/CLAUDE.md)
#   3. Persist Claude Code installs; activate the pinned or newest version; prune
#   4. Symlink auxiliary user state (ssh, gitconfig, ~/.config, history, ~/.claude)
#   5. Export env: CLAUDE_CONFIG_DIR, auth tokens from add-on options, STARTUP_CMD
#   6. Run the user's init.sh hook
#   7. Start tmux detached (runs STARTUP_CMD at boot); tmux-session.sh pipes
#      the pane into logs/ via s6-log
#   8. Run ttyd in a bounded restart loop; tmux's `-A` reattaches the browser
#
# All Claude Code state (auth, MCP config, plugins, conversation history, channels)
# lives under $CLAUDE_CONFIG_DIR which points at the persistent /config volume,
# so it survives container restarts and add-on updates.
#
# Robustness model: `set -euo pipefail` for the few steps that must succeed
# (persistent dir, env, tmux). Everything else is a function invoked as
# `step || bashio::log.warning ...` so a failure is logged and boot continues.
# Note `set -e` is suspended inside such a function, so each of them chains
# its own critical commands with && / return and never leaves half-done state.

set -euo pipefail

CLAUDE_DIR=/config/claude-config
CLAUDE_INSTALLS="${CLAUDE_DIR}/claude-installations"
DEFAULTS_DIR=/opt/claude-defaults
SESSION_LOG_DIR="${CLAUDE_DIR}/logs"

# --- Option reader ---------------------------------------------------------
# bashio first (applies the schema), raw /data/options.json second, empty
# string last. bashio::config fetches the options from the Supervisor API
# (bashio::addon.config), which only exists when running as an add-on;
# without SUPERVISOR_TOKEN (local docker testing) it just logs errors, so
# skip it there. Its default argument is `${2:-null}`, so an empty-string
# default is ignored and a missing/null key prints the literal string
# "null" — map that to empty, or `bash -lc null` / a token of "null" follows.
opt() {
    local key="$1" value=''
    if [ -n "${SUPERVISOR_TOKEN:-}" ]; then
        value=$(bashio::config "${key}" 2>/dev/null) || value=''
        if [ "${value}" = null ]; then
            value=''
        fi
    fi
    if [ -z "${value}" ] && [ -f /data/options.json ]; then
        value=$(jq -r --arg k "${key}" '.[$k] // ""' /data/options.json 2>/dev/null) || value=''
    fi
    printf '%s' "${value}"
}

# --- Persistent storage (critical) -----------------------------------------
mkdir -p "${CLAUDE_DIR}"
chmod 700 "${CLAUDE_DIR}"

# --- Seed defaults (first boot only; existing files are never touched) ------
seed_defaults() {
    if [ ! -f "${CLAUDE_DIR}/settings.json" ]; then
        cp "${DEFAULTS_DIR}/settings.json" "${CLAUDE_DIR}/settings.json" \
            && bashio::log.info "Seeded default settings.json (system ripgrep, deny rules for secrets.yaml/.storage/recorder DB)"
    fi
    # Project instructions for Claude when it runs in /config: what this
    # directory is, what not to touch, which helpers exist.
    if [ ! -f /config/CLAUDE.md ]; then
        cp "${DEFAULTS_DIR}/CLAUDE.md" /config/CLAUDE.md \
            && bashio::log.info "Seeded /config/CLAUDE.md"
    fi
}
seed_defaults || bashio::log.warning "Seeding defaults failed (continuing)"

# --- Persist Claude Code installations ------------------------------------
# Claude's native installer writes the binary to /root/.local/share/claude/
# versions/X.Y.Z and points /root/.local/bin/claude at the active version.
# Neither path is on the persistent volume by default, so both auto-updates
# and manual `claude install X` calls vanish on add-on restart.
#
# Fix: symlink /root/.local/share/claude → persistent volume; on boot,
# re-point /root/.local/bin/claude at the pinned (or newest) installed version.
persist_installs() {
    mkdir -p "${CLAUDE_INSTALLS}/versions" || return 1

    # Copy any versions the image ships that aren't already in persistent
    # storage. Covers (a) first-ever boot — persistent is empty, image seeds
    # it; and (b) image upgrades — a new image pin lands in persistent
    # without disturbing any versions the user already has.
    local img_ver ver_name
    if [ ! -L /root/.local/share/claude ] && [ -d /root/.local/share/claude/versions ]; then
        for img_ver in /root/.local/share/claude/versions/*; do
            [ -e "${img_ver}" ] || continue
            ver_name="$(basename "${img_ver}")"
            if [ ! -e "${CLAUDE_INSTALLS}/versions/${ver_name}" ]; then
                cp -a "${img_ver}" "${CLAUDE_INSTALLS}/versions/" \
                    && bashio::log.info "Seeded Claude Code version from image: ${ver_name}"
            fi
        done
    fi

    # Replace the image's install dir with a symlink into persistent storage.
    if [ ! -L /root/.local/share/claude ] \
       || [ "$(readlink /root/.local/share/claude)" != "${CLAUDE_INSTALLS}" ]; then
        rm -rf /root/.local/share/claude \
            && ln -sfn "${CLAUDE_INSTALLS}" /root/.local/share/claude \
            || return 1
    fi
}
persist_installs || bashio::log.warning "Persisting Claude Code installs failed; 'claude install' and auto-updates may not stick this boot"

# --- Activate a Claude Code version ---------------------------------------
# /root/.local/bin/claude lives in the image and is reset on every restart,
# so it is re-pointed here. Order of preference:
#   1. `claude_version` add-on option, if that version is installed (pin;
#      also disables the auto-updater so it isn't silently superseded)
#   2. newest installed version by `sort -V`
ACTIVE_VER=""
# Installed versions, oldest first by `sort -V`. Only entries that look like a
# version AND are an executable file or a directory count; anything else the
# installer may leave behind (a partial download cut short by a restart, a
# lock/temp file) must never become the active version or block pruning.
installed_versions() {
    local entry name
    for entry in "${CLAUDE_INSTALLS}"/versions/*; do
        name="$(basename "${entry}")"
        [[ "${name}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][A-Za-z0-9.]+)?$ ]] || continue
        [ -x "${entry}" ] || [ -d "${entry}" ] || continue
        printf '%s\n' "${name}"
    done | sort -V
}
activate_claude() {
    local pin newest
    pin=$(opt claude_version)
    newest=$(installed_versions | tail -n 1) || newest=""

    if [ -n "${pin}" ]; then
        if [ -e "${CLAUDE_INSTALLS}/versions/${pin}" ]; then
            ACTIVE_VER="${pin}"
            export DISABLE_AUTOUPDATER=1
            bashio::log.info "Pinned Claude Code version: ${pin} (auto-updater disabled while pinned)"
        else
            bashio::log.warning "claude_version ${pin} is not installed; run 'claude install ${pin}' once from the terminal, then restart; using newest ${newest:-<none>} instead"
            ACTIVE_VER="${newest}"
        fi
    else
        ACTIVE_VER="${newest}"
    fi

    if [ -z "${ACTIVE_VER}" ]; then
        bashio::log.warning "No Claude Code version found under ${CLAUDE_INSTALLS}/versions; 'claude' will not work until one is installed"
        return 0
    fi

    mkdir -p /root/.local/bin || return 1
    # Symlink target MUST be lexically under .local/share/claude/versions/ —
    # not /config/claude-config/... — even though that's the same directory
    # via the /root/.local/share/claude symlink above. Claude Code >= 2.1.207
    # only self-manages (auto-updates, `claude update`, version cleanup) a
    # launcher whose symlink target resolves lexically inside
    # ~/.local/share/claude/versions/; any other target (including a path
    # that happens to point at the same inode through /config/...) is treated
    # as a "custom launcher" that Claude Code will not touch. Pointing
    # straight at ${CLAUDE_INSTALLS}/versions/... made every update install
    # successfully but never activate until the add-on was restarted, and
    # disabled the updater's own version cleanup. See
    # https://code.claude.com/docs/en/setup
    ln -sfn "/root/.local/share/claude/versions/${ACTIVE_VER}" /root/.local/bin/claude || return 1
    bashio::log.info "Active Claude Code version: ${ACTIVE_VER}"
}
activate_claude || bashio::log.warning "Activating a Claude Code version failed; 'claude' may not be on PATH this boot"

# --- Prune old installs ----------------------------------------------------
# Every auto-update leaves the previous binary (~200 MB each) behind. Keep
# the newest two plus whatever is active; delete the rest. The active one is
# never deleted, even if it sorts below the newest two (i.e. an old pin).
# Entries that are not installed versions (see installed_versions) are stray
# leftovers and are deleted too; nothing is running yet, so nothing owns them.
prune_installs() {
    local keep entry name
    keep=$(installed_versions | tail -n 2) || return 0
    for entry in "${CLAUDE_INSTALLS}"/versions/*; do
        [ -e "${entry}" ] || continue
        name="$(basename "${entry}")"
        [ "${name}" = "${ACTIVE_VER}" ] && continue
        grep -qxF "${name}" <<< "${keep}" && continue
        # Versions are plain binaries, but tolerate a directory layout too.
        rm -rf "${entry}" && bashio::log.info "Pruned old Claude Code version: ${name}"
    done
}
prune_installs || bashio::log.warning "Pruning old Claude Code versions failed (continuing)"

# --- Persist auxiliary user state -----------------------------------------
# CLAUDE_CONFIG_DIR covers everything Claude Code writes. The paths below are
# NOT under Claude's control but are still "config the user set up" (SSH keys
# for git push, gitconfig identity, GitHub CLI auth, shell history). Symlink
# them into the persistent volume so they survive restarts and updates.
ensure_symlink() {
    local src="$1" target="$2" stash
    # Already the right symlink → nothing to do (an unconditional rm -rf here
    # would drop every link briefly on every boot).
    [ "$(readlink -- "${src}" 2>/dev/null)" = "${target}" ] && return 0
    if [ -e "${src}" ] && [ ! -L "${src}" ]; then
        # A real file/dir is in the way. If it has content, stash it rather
        # than destroy it: it might be something the user created before the
        # symlink existed. Empty ones are just removed.
        if { [ -d "${src}" ] && [ -n "$(ls -A "${src}" 2>/dev/null)" ]; } \
           || { [ -f "${src}" ] && [ -s "${src}" ]; }; then
            stash="${CLAUDE_DIR}/migrated/$(basename "${src}").$(date +%s)"
            mkdir -p "${CLAUDE_DIR}/migrated" && mv "${src}" "${stash}" || return 1
            bashio::log.warning "Moved non-empty ${src} to ${stash} before symlinking it to ${target}"
        else
            rm -rf "${src}" || return 1
        fi
    fi
    ln -sfn "${target}" "${src}"
}

migrate_gh_config() {
    # One-time migration: 2.0.x kept `gh` auth in config-gh/; move into
    # dot-config/ so the broader /root/.config symlink picks it up.
    if [ -d "${CLAUDE_DIR}/config-gh" ] && [ ! -e "${CLAUDE_DIR}/dot-config/gh" ]; then
        mkdir -p "${CLAUDE_DIR}/dot-config" \
            && mv "${CLAUDE_DIR}/config-gh" "${CLAUDE_DIR}/dot-config/gh" \
            && bashio::log.info "Migrated gh config to dot-config/gh"
    fi
}
migrate_gh_config || bashio::log.warning "gh config migration failed (continuing)"

link_user_state() {
    local rc=0
    mkdir -p "${CLAUDE_DIR}/ssh" "${CLAUDE_DIR}/dot-config" || return 1
    chmod 700 "${CLAUDE_DIR}/ssh" || rc=1
    touch "${CLAUDE_DIR}/gitconfig" "${CLAUDE_DIR}/bash_history" || rc=1
    ensure_symlink /root/.ssh          "${CLAUDE_DIR}/ssh"          || rc=1
    ensure_symlink /root/.gitconfig    "${CLAUDE_DIR}/gitconfig"    || rc=1
    # Broad ~/.config symlink: covers gh, npm, aws, gcloud, fly, and any
    # future CLI that stores config under ~/.config. One symlink, rather
    # than chasing each tool individually.
    ensure_symlink /root/.config       "${CLAUDE_DIR}/dot-config"   || rc=1
    ensure_symlink /root/.bash_history "${CLAUDE_DIR}/bash_history" || rc=1
    # ~/.claude → persistent volume. CLAUDE_CONFIG_DIR (exported below)
    # redirects Claude Code's own reads/writes, but plugins and channels
    # (e.g. the Telegram bot — a separate bun process) use the literal
    # $HOME/.claude path and don't honour the env var. The symlink makes both
    # paths land on persistent storage.
    ensure_symlink /root/.claude       "${CLAUDE_DIR}"              || rc=1
    # Tighten any keys the user has dropped into the persistent SSH dir.
    find "${CLAUDE_DIR}/ssh" -type f -exec chmod 600 {} \; || rc=1
    return "${rc}"
}
link_user_state || bashio::log.warning "One or more user-state symlinks failed; some state may not persist this boot"

# --- Environment (critical) -----------------------------------------------
# CLAUDE_CONFIG_DIR is the official knob for relocating Claude Code state.
# Everything exported here propagates through tmux → bash → claude, and
# through ttyd → bash → tmux, because both are started by this process.
export CLAUDE_CONFIG_DIR="${CLAUDE_DIR}"
export HOME=/root

# --- Auth from add-on options --------------------------------------------
# Values go into the environment only; they are never placed on a command
# line (which would show up in `ps` and the session log). Precedence when
# both are set follows Claude Code's docs: ANTHROPIC_API_KEY (rank 3) is
# consulted before CLAUDE_CODE_OAUTH_TOKEN (rank 5).
# https://code.claude.com/docs/en/authentication#authentication-precedence
OAUTH_TOKEN=$(opt oauth_token)
API_KEY=$(opt api_key)
if [ -n "${OAUTH_TOKEN}" ]; then
    export CLAUDE_CODE_OAUTH_TOKEN="${OAUTH_TOKEN}"
    bashio::log.info "oauth_token option set (value not shown); exported as CLAUDE_CODE_OAUTH_TOKEN"
fi
if [ -n "${API_KEY}" ]; then
    export ANTHROPIC_API_KEY="${API_KEY}"
    bashio::log.info "api_key option set (value not shown); exported as ANTHROPIC_API_KEY"
fi
if [ -n "${OAUTH_TOKEN}" ] && [ -n "${API_KEY}" ]; then
    bashio::log.warning "Both oauth_token and api_key are set; Claude Code uses ANTHROPIC_API_KEY first (see https://code.claude.com/docs/en/authentication#authentication-precedence). Clear api_key to use the subscription token."
fi
unset OAUTH_TOKEN API_KEY

# --- Optional startup command ---------------------------------------------
# Exported so the tmux wrapper script can read it. Empty (default) → plain
# bash. Otherwise → run the command in a restart loop (see tmux-session.sh).
STARTUP_CMD=$(opt startup_command)
export STARTUP_CMD
if [ -n "${STARTUP_CMD}" ]; then
    # People prefix `TELEGRAM_BOT_TOKEN=... claude ...`; keep secrets out of
    # the Supervisor log (visible in the HA UI, included in diagnostics).
    redacted=$(printf '%s' "${STARTUP_CMD}" \
        | sed -E 's/([A-Za-z_][A-Za-z0-9_]*(TOKEN|KEY|SECRET|PASSWORD)[A-Za-z0-9_]*=)[^[:space:]]+/\1<redacted>/g')
    bashio::log.info "Startup command: ${redacted}"
    unset redacted
else
    bashio::log.info "No startup command configured; tmux will launch a plain bash shell"
fi

# --- Session log -----------------------------------------------------------
# Everything the tmux pane prints goes to logs/current (raw, with escape
# sequences) so a crash of the startup command can be diagnosed after the
# fact. The pipe itself is opened by tmux-session.sh (so every session gets
# one, not just the first) and is an s6-log process, which rotates the file
# while the add-on runs: 2 MB per file, 3 rotated files kept, ~8 MB tops.
# The pane echoes whatever was typed or printed, including login URLs and
# device codes, so the directory is 0700 like the rest of claude-config.
setup_session_log() {
    mkdir -p "${SESSION_LOG_DIR}" && chmod 700 "${SESSION_LOG_DIR}"
}
setup_session_log || bashio::log.warning "Session log directory setup failed; the tmux session may not be logged"

# --- User init hook -------------------------------------------------------
# If /config/claude-config/init.sh exists, run it in a subshell. Lets users
# run arbitrary shell at boot — extra symlinks, one-off setup, background
# helpers. Run in a subshell (rather than sourced) so an `exit` inside the
# hook can't terminate run.sh and kill the boot; the tradeoff is that
# exports inside init.sh no longer propagate to run.sh or the rest of the
# boot — use bashrc.local for env vars instead.
run_user_init() {
    local hook="${CLAUDE_DIR}/init.sh"
    [ -f "${hook}" ] || return 0
    bashio::log.info "Running user init hook: ${hook}"
    # shellcheck disable=SC1090
    ( . "${hook}" )
}
run_user_init || bashio::log.warning "User init hook exited non-zero (ignored)"

# --- Start tmux session at container boot (critical) ----------------------
# This runs STARTUP_CMD at boot, BEFORE any browser is attached, so
# always-on commands (e.g. `claude -c --channels plugin:telegram@...`) start
# immediately and stay running even if the user never opens the web terminal.
# `-d` creates the session detached. ttyd attaches to it later.
if ! tmux has-session -t claude-main 2>/dev/null; then
    tmux new-session -d -s claude-main -c /config /opt/tmux-session.sh
    bashio::log.info "Started detached tmux session 'claude-main'"
fi

bashio::log.info "Session log: ${SESSION_LOG_DIR}/current"

# --- Launch web terminal ---------------------------------------------------
# ttyd attaches to the existing tmux session on each browser connect.
# `new-session -A` is create-or-attach: if the session died (rare; e.g. user
# typed `exit` after STARTUP_CMD finished and tmux became empty), a fresh one
# is created so the web terminal still works.
#
# ttyd --client-option flags, some ttyd's own, some passed through to
# xterm.js:
#   disableLeaveAlert=true → suppress the browser's "Leave site?" prompt on
#                            tab close; the tmux session survives a closed
#                            tab (that's the whole point), so the warning is
#                            just noise.
#   rendererType=dom       → render real DOM text instead of a WebGL canvas
#                            (ttyd 1.7.7's default). DOM text is selectable
#                            and copyable inside WKWebView / the HA Companion
#                            app, where the canvas renderer gave nothing to
#                            select. Slightly slower on huge outputs; fine
#                            for a chat-style TUI.
#   cursorBlink=true       → visible cursor blink (xterm.js)
#   fontSize=14            → slightly larger than default 12px (xterm.js)
#   scrollback=5000        → xterm.js scrollback lines, separate from tmux
#                            history (xterm.js)
# No --max-clients: tmux already shares one session across every connected
# client (that's how "reopen the browser and reattach" works), so capping at
# 1 only served to refuse a legitimate second tab.
# Intentionally NOT setting fontFamily: xterm.js's default monospace stack
# renders correctly; custom values with commas / quoted family names broke
# letter spacing in practice.
#
# Restart loop: ttyd occasionally dies (e.g. a client disconnect race). A
# bounded loop restarts it so a blip doesn't cost a full container restart
# and the tmux session (with a running startup command) survives. 5 exits
# within 120s means something is really wrong → exit 1 and let the
# Supervisor / watchdog restart the whole add-on.
TTYD_PID=""
on_stop() {
    trap - TERM INT
    bashio::log.info "Stop signal received; shutting down ttyd"
    if [ -n "${TTYD_PID}" ]; then
        kill -TERM "${TTYD_PID}" 2>/dev/null || true
        wait "${TTYD_PID}" 2>/dev/null || true
    fi
    exit 0
}
trap on_stop TERM INT

bashio::log.info "Starting ttyd on port 7681"
EXIT_TIMES=()
while :; do
    ttyd \
        --port 7681 \
        --interface 0.0.0.0 \
        --writable \
        --ping-interval 30 \
        --client-option 'disableLeaveAlert=true' \
        --client-option 'rendererType=dom' \
        --client-option 'cursorBlink=true' \
        --client-option 'fontSize=14' \
        --client-option 'scrollback=5000' \
        bash -lc 'tmux new-session -A -s claude-main -c /config /opt/tmux-session.sh' &
    TTYD_PID=$!
    rc=0
    wait "${TTYD_PID}" || rc=$?
    TTYD_PID=""

    now=$(date +%s)
    recent=()
    for t in "${EXIT_TIMES[@]}"; do
        [ $((now - t)) -lt 120 ] && recent+=("${t}")
    done
    recent+=("${now}")
    EXIT_TIMES=("${recent[@]}")
    if [ "${#EXIT_TIMES[@]}" -ge 5 ]; then
        bashio::log.error "ttyd exited 5 times within 120s (last exit code ${rc}); giving up so the Supervisor restarts the add-on"
        exit 1
    fi
    bashio::log.warning "ttyd exited with code ${rc}; restarting in 2s"
    sleep 2
done
