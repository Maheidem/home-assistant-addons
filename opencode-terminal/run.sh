#!/usr/bin/with-contenv bashio
# OpenCode add-on — boot script.
#
# Responsibilities:
#   1. Ensure persistent storage exists at /data/opencode (add-on private volume)
#      and at /config (addon_config — user-editable, host-visible).
#   2. Symlink /root/* paths into /data/opencode so SSH keys, git config,
#      gh auth, shell history, and OpenCode's own state all persist.
#   3. Seed a default opencode.json in /config on first boot.
#   4. Read HA options for secrets (API keys) and export them as env vars so
#      opencode.json can reference them with `{env:FOO}`.
#   5. Launch opencode web in the foreground as PID 1's single child.
#
# Persistence model (intentionally different from claude-terminal):
#   /data/opencode          → add-on private, included in per-add-on backups.
#                              Holds OpenCode state (SQLite DB, auth.json,
#                              snapshots, tool-output, logs), SSH keys, git
#                              identity, shell history, ~/.config/* tools.
#   /config  (= /addon_configs/opencode_terminal/ on host)
#                            → user-editable, host-visible via Samba/File
#                              Editor, included in per-add-on backups.
#                              Holds opencode.json, bashrc.local, init.sh.

set -euo pipefail

# --- Paths ----------------------------------------------------------------
DATA_DIR=/data/opencode
CONFIG_DIR=/config
OPENCODE_JSON="${CONFIG_DIR}/opencode.json"
SCHEMA_VERSION=1
SCHEMA_MARKER="${DATA_DIR}/.schema-version"

# --- Persistent storage ---------------------------------------------------
mkdir -p "${DATA_DIR}" \
         "${DATA_DIR}/ssh" \
         "${DATA_DIR}/dot-config" \
         "${DATA_DIR}/opencode-state/config" \
         "${DATA_DIR}/opencode-state/share"
chmod 700 "${DATA_DIR}"
chmod 700 "${DATA_DIR}/ssh"
mkdir -p "${CONFIG_DIR}"

# --- Schema-version migrations -------------------------------------------
# No migrations at v1, but the marker is here so future bumps have a
# well-defined starting point.
CURRENT_SCHEMA=0
if [ -f "${SCHEMA_MARKER}" ]; then
    CURRENT_SCHEMA=$(cat "${SCHEMA_MARKER}" 2>/dev/null || echo 0)
fi
if [ "${CURRENT_SCHEMA}" -lt "${SCHEMA_VERSION}" ]; then
    # Future migrations:
    #   case "${CURRENT_SCHEMA}" in
    #       0) bashio::log.info "Migrating 0 → 1: <describe>" ;;
    #   esac
    echo "${SCHEMA_VERSION}" > "${SCHEMA_MARKER}"
    bashio::log.info "Data schema version: ${SCHEMA_VERSION}"
fi

# --- ensure_symlink helper ------------------------------------------------
# Remove whatever's at $src (file, dir, or broken link) and replace with a
# symlink to $target. Target must already exist (we mkdir above).
ensure_symlink() {
    local src="$1" target="$2"
    rm -rf "${src}" 2>/dev/null || true
    ln -sf "${target}" "${src}"
}

# --- Persist auxiliary user state ----------------------------------------
# Unlike claude-terminal (where CLAUDE_CONFIG_DIR covered most Claude Code
# writes), OpenCode has no single env var to relocate everything. So we
# symlink both of its known state roots:
#   ~/.config/opencode       → config (opencode.json, agents/, skills/, ...)
#   ~/.local/share/opencode  → runtime state (SQLite DB, auth, snapshots, ...)
#
# The broader home-dir symlinks below are identical in spirit to
# claude-terminal — cover gh, npm, aws, gcloud, SSH, git, shell history.
touch "${DATA_DIR}/gitconfig" "${DATA_DIR}/bash_history"

# OpenCode config dir — normally ~/.config/opencode. The parent ~/.config
# symlink below would cover this, but we want a dedicated persistence slot
# so users can wipe their whole ~/.config if needed without nuking opencode.
mkdir -p /root/.config
ensure_symlink /root/.config/opencode      "${DATA_DIR}/opencode-state/config"

# OpenCode runtime state dir — ~/.local/share/opencode.
mkdir -p /root/.local/share
ensure_symlink /root/.local/share/opencode "${DATA_DIR}/opencode-state/share"

# Standard home-dir persistence (SSH, git, bash history, broad ~/.config).
ensure_symlink /root/.ssh          "${DATA_DIR}/ssh"
ensure_symlink /root/.gitconfig    "${DATA_DIR}/gitconfig"
ensure_symlink /root/.bash_history "${DATA_DIR}/bash_history"

# ~/.config catch-all for gh, npm, aws, gcloud, fly, and future CLIs.
# NOTE: we already symlinked /root/.config/opencode above. Replacing
# /root/.config wholesale would blow that away, so we mirror subdirectories
# one level down instead of symlinking /root/.config itself.
mkdir -p "${DATA_DIR}/dot-config"
for sub_real in "${DATA_DIR}/dot-config"/*; do
    [ -e "${sub_real}" ] || continue
    sub_name="$(basename "${sub_real}")"
    [ "${sub_name}" = "opencode" ] && continue  # already handled above
    ensure_symlink "/root/.config/${sub_name}" "${sub_real}"
done

# Tighten any keys the user has dropped into the persistent SSH dir.
if [ -d "${DATA_DIR}/ssh" ]; then
    find "${DATA_DIR}/ssh" -type f -exec chmod 600 {} \;
fi

# --- Seed default opencode.json ------------------------------------------
# Only runs on first boot (or if the user has deleted opencode.json). We
# keep the template small on purpose — OpenCode's schema lets users layer
# providers, MCP servers, and agents in however they like.
if [ ! -f "${OPENCODE_JSON}" ]; then
    cat > "${OPENCODE_JSON}" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "autoupdate": false,
  "permission": {
    "edit": "ask",
    "bash": "ask",
    "webfetch": "allow"
  },
  "provider": {},
  "mcp": {}
}
EOF
    bashio::log.info "Seeded default opencode.json at ${OPENCODE_JSON}"
    bashio::log.info "Edit it via Samba or HA File Editor at /addon_configs/opencode_terminal/opencode.json"
fi

# --- Environment ----------------------------------------------------------
# OPENCODE_CONFIG points OpenCode at the user-editable config file in
# addon_config rather than the default ~/.config/opencode/opencode.json.
# Users who want to layer a project-local opencode.json can still do so —
# project config overrides this file.
export OPENCODE_CONFIG="${OPENCODE_JSON}"
export HOME=/root

# --- Read HA options -----------------------------------------------------
# Primary source is bashio (queries the supervisor); fallback to reading
# /data/options.json directly so local `podman run` testing works without
# a full HA supervisor stack.
read_option() {
    local key="$1" val
    val=$(bashio::config "${key}" '' 2>/dev/null || echo '')
    if [ -z "${val}" ] && [ -f /data/options.json ]; then
        val=$(jq -r ".${key} // empty" /data/options.json 2>/dev/null || echo '')
    fi
    printf '%s' "${val}"
}

# Export non-empty secrets as env vars. Users reference them from opencode.json
# with `{env:ZHIPU_API_KEY}`, etc.
for key in zhipu_api_key anthropic_api_key openai_api_key waha_api_key waha_api_url; do
    val=$(read_option "${key}")
    if [ -n "${val}" ]; then
        # Convert snake_case → SHOUTY_SNAKE_CASE for env-var convention.
        ename=$(echo "${key}" | tr '[:lower:]' '[:upper:]')
        export "${ename}=${val}"
        bashio::log.info "Exported ${ename} from add-on options"
    fi
done

# Log level — OpenCode accepts DEBUG|INFO|WARN|ERROR (uppercase). We take
# lowercase from the HA UI (to match bashio conventions) and upcase here.
OPENCODE_LOG_LEVEL=$(read_option log_level)
OPENCODE_LOG_LEVEL=$(echo "${OPENCODE_LOG_LEVEL:-info}" | tr '[:lower:]' '[:upper:]')
export OPENCODE_LOG_LEVEL

# Extra env var block (one KEY=VALUE per line). Useful for provider keys
# beyond the curated five or per-deployment overrides.
EXTRA_ENV=$(read_option extra_env)
if [ -n "${EXTRA_ENV}" ]; then
    while IFS= read -r line; do
        [ -z "${line}" ] && continue
        case "${line}" in \#*) continue ;; esac
        if [[ "${line}" == *=* ]]; then
            export "${line?}"
            bashio::log.info "Exported extra env: ${line%%=*}"
        else
            bashio::log.warning "Skipping malformed extra_env line: ${line}"
        fi
    done <<< "${EXTRA_ENV}"
fi

# --- User init hook -------------------------------------------------------
# If /config/init.sh exists, source it. Lets users run arbitrary shell at
# boot — extra symlinks, exports, one-off setup. Non-fatal on failure.
USER_INIT="${CONFIG_DIR}/init.sh"
if [ -f "${USER_INIT}" ]; then
    bashio::log.info "Running user init hook: ${USER_INIT}"
    # shellcheck disable=SC1090
    . "${USER_INIT}" || bashio::log.warning "User init hook exited non-zero (ignored)"
fi

# --- Welcome banner ------------------------------------------------------
# Written every boot (idempotent). Rarely seen — the primary UI is the web
# server — but if opencode web crashes, the fallback bash in opencode-boot.sh
# shows it so the user has a clue what to do.
cat > /etc/profile.d/01-opencode-terminal-welcome.sh <<'EOF'
if [[ $- == *i* ]] && [ -z "${OPENCODE_TERMINAL_WELCOMED:-}" ]; then
    export OPENCODE_TERMINAL_WELCOMED=1
    cat <<'BANNER'

  OpenCode
  ────────
  The web UI is the primary surface. If you're seeing this prompt,
  opencode web has exited — check the add-on logs (Settings → Add-ons →
  OpenCode → Log) for the error.

  Config:    /config/opencode.json   (edit on the host at
             /addon_configs/opencode_terminal/opencode.json)
  State:     /data/opencode/         (SQLite DB, auth, snapshots)
  Env:       log_level, *_api_key, extra_env — see add-on Configuration tab

  Type `opencode` for the TUI, or `exit` then restart the add-on to
  relaunch the web UI.

BANNER
fi
EOF

# --- Launch OpenCode web -------------------------------------------------
# Foreground exec: opencode web becomes PID 1's single child, so SIGTERM
# from the supervisor propagates directly. All setup above is done;
# opencode-boot.sh is the last hop so we have a single place to tweak the
# invocation without touching the rest of this script.
bashio::log.info "Starting OpenCode web on 0.0.0.0:7682 (log_level=${OPENCODE_LOG_LEVEL})"
exec /opt/opencode-boot.sh
