#!/usr/bin/with-contenv bashio

# Initialize environment for Claude Code CLI
init_environment() {
    export HOME="/root"
    export PATH="/root/.local/bin:$PATH"

    # Ensure persistent storage directories exist
    mkdir -p /config/claude-config/.claude
    mkdir -p /config/claude-config/.ssh
    mkdir -p /config/claude-config/.config-gh
    chmod 755 /config/claude-config
    chmod 700 /config/claude-config/.ssh

    # --- Symlink all user data into persistent volume ---
    # Claude CLI
    rm -rf /root/.claude
    rm -f /root/.claude.json
    ln -sf /config/claude-config/.claude /root/.claude
    ln -sf /config/claude-config/.claude.json /root/.claude.json

    # Git config
    rm -f /root/.gitconfig
    ln -sf /config/claude-config/.gitconfig /root/.gitconfig

    # SSH keys
    rm -rf /root/.ssh
    ln -sf /config/claude-config/.ssh /root/.ssh

    # GitHub CLI auth
    mkdir -p /root/.config
    rm -rf /root/.config/gh
    ln -sf /config/claude-config/.config-gh /root/.config/gh

    # Bash history
    rm -f /root/.bash_history
    ln -sf /config/claude-config/.bash_history /root/.bash_history
    touch /config/claude-config/.bash_history

    # --- Restore permissions on existing auth files ---
    if [ -f "/config/claude-config/.claude.json" ]; then
        chmod 600 /config/claude-config/.claude.json
        bashio::log.info "Restored existing Claude configuration"
    fi

    if [ -d "/config/claude-config/.claude" ]; then
        find /config/claude-config/.claude -type f -exec chmod 600 {} \;
        bashio::log.info "Restored existing Claude directory"
    fi

    if [ -d "/config/claude-config/.ssh" ]; then
        find /config/claude-config/.ssh -type f -exec chmod 600 {} \;
        bashio::log.info "Restored existing SSH keys"
    fi

    # Copy default Claude settings into persistent volume if not already present
    if [ -f "/opt/claude-defaults/settings.json" ] && [ ! -f "/config/claude-config/.claude/settings.json" ]; then
        cp /opt/claude-defaults/settings.json /config/claude-config/.claude/settings.json
        bashio::log.info "Installed default Claude settings (USE_BUILTIN_RIPGREP=0)"
    fi

    bashio::log.info "Environment initialized — all user data persisted to /config/claude-config/"
}

# Setup session picker script
setup_session_picker() {
    # Copy session picker script from built-in location
    if [ -f "/opt/scripts/claude-session-picker.sh" ]; then
        if ! cp /opt/scripts/claude-session-picker.sh /usr/local/bin/claude-session-picker; then
            bashio::log.error "Failed to copy claude-session-picker script"
            exit 1
        fi
        chmod +x /usr/local/bin/claude-session-picker
        bashio::log.info "Session picker script installed successfully"
    else
        bashio::log.warning "Session picker script not found, using auto-launch mode only"
    fi
}

# Determine Claude launch command based on configuration
get_claude_launch_command() {
    local auto_launch_claude
    local persistent_sessions

    # Get configuration values
    auto_launch_claude=$(bashio::config 'auto_launch_claude' 'true')
    persistent_sessions=$(bashio::config 'persistent_sessions' 'true')

    # Check if auto-session manager should be used
    if [ "$persistent_sessions" = "true" ] && [ -f "/opt/scripts/auto-session-manager.sh" ]; then
        # Use transparent session management (tmux-backed)
        echo "/opt/scripts/auto-session-manager.sh"
    elif [ "$auto_launch_claude" = "true" ]; then
        # Auto-launch Claude in a tmux session for browser-reconnect persistence
        echo "tmux new-session -A -s claude-main -c /config claude"
    else
        # Interactive session picker wrapped in tmux for browser-reconnect persistence
        if [ -f /usr/local/bin/claude-session-picker ]; then
            echo "tmux new-session -A -s claude-main -c /config /usr/local/bin/claude-session-picker"
        else
            # Fallback if session picker is missing
            bashio::log.warning "Session picker not found, falling back to auto-launch"
            echo "tmux new-session -A -s claude-main -c /config claude"
        fi
    fi
}

# Start credential monitoring service
start_credential_monitor() {
    if [ -f "/opt/scripts/credential-monitor.sh" ]; then
        bashio::log.info "Starting credential monitoring service..."
        /opt/scripts/credential-monitor.sh &
        MONITOR_PID=$!
        bashio::log.info "Credential monitor started (PID: ${MONITOR_PID})"
    else
        bashio::log.warning "Credential monitor script not found"
    fi
}

# Start main web terminal
start_web_terminal() {
    local port=7681
    bashio::log.info "Starting web terminal on port ${port}..."

    # Log environment information for debugging
    bashio::log.info "HOME=${HOME}"

    # Start credential monitoring in background
    start_credential_monitor

    # Get the appropriate launch command based on configuration
    local launch_command
    launch_command=$(get_claude_launch_command)

    # Log the configuration being used
    local auto_launch_claude
    auto_launch_claude=$(bashio::config 'auto_launch_claude' 'true')
    bashio::log.info "Auto-launch Claude: ${auto_launch_claude}"

    # Run ttyd web terminal
    # --ping-interval 30: WebSocket keepalive to prevent silent drops
    # --max-clients 1: single session per tmux design; prevents competing attachments
    exec ttyd \
        --port "${port}" \
        --interface 0.0.0.0 \
        --writable \
        --ping-interval 30 \
        --max-clients 1 \
        bash -c "$launch_command"
}

# Main execution
main() {
    bashio::log.info "Initializing Claude Terminal add-on..."

    init_environment
    setup_session_picker
    start_web_terminal
}

# Execute main function
main "$@"
