#!/bin/bash

# Credential Monitor - Ensure Claude authentication files have correct permissions
# Symlinks in run.sh already point /root/.claude and /root/.claude.json to
# /config/claude-config, so no file copying is needed here.

CREDENTIAL_DIR="/config/claude-config"
LOG_PREFIX="credential-monitor"

log_info() {
    echo "[$LOG_PREFIX] $1"
}

# Enforce correct permissions on credential files
enforce_permissions() {
    # Fix permissions on any credential files written by Claude
    find "$CREDENTIAL_DIR" -type f 2>/dev/null | while read -r file; do
        local current_perms
        current_perms=$(stat -c "%a" "$file" 2>/dev/null)
        if [ "$current_perms" != "600" ]; then
            chmod 600 "$file"
            log_info "Fixed permissions on: $file"
        fi
    done
}

# Handle cleanup on exit
cleanup() {
    log_info "Credential monitor stopping..."
    exit 0
}

trap cleanup EXIT INT TERM

log_info "Starting credential permission monitor..."

while true; do
    enforce_permissions
    sleep 30
done
