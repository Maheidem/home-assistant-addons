#!/usr/bin/with-contenv bashio

# Initialize environment for Claude Code CLI
init_environment() {
    # Ensure claude-config directory exists for persistent storage
    mkdir -p /config/claude-config
    chmod 755 /config/claude-config

    # Create subdirectories for Claude CLI storage
    mkdir -p /config/claude-config/.claude
    mkdir -p /root/.config
    
    # Remove existing links if they exist and create fresh symlinks
    rm -rf /root/.config/anthropic
    rm -rf /root/.claude
    rm -f /root/.claude.json
    
    # Create symlinks for ALL Claude storage locations
    ln -sf /config/claude-config /root/.config/anthropic
    ln -sf /config/claude-config/.claude /root/.claude
    ln -sf /config/claude-config/.claude.json /root/.claude.json

    # Restore existing authentication files if they exist
    if [ -f "/config/claude-config/.claude.json" ]; then
        chmod 600 /config/claude-config/.claude.json
        bashio::log.info "Restored existing Claude configuration"
    fi
    
    # Restore .claude directory contents if they exist
    if [ -d "/config/claude-config/.claude" ]; then
        find /config/claude-config/.claude -type f -exec chmod 600 {} \;
        bashio::log.info "Restored existing Claude directory"
    fi

    # Legacy credential files (keeping for backward compatibility)
    if [ -f "/config/claude-config/session_key" ]; then
        chmod 600 /config/claude-config/session_key
    fi
    if [ -f "/config/claude-config/client.json" ]; then
        chmod 600 /config/claude-config/client.json
    fi

    # Set environment variables for Claude Code CLI
    export ANTHROPIC_CONFIG_DIR="/config/claude-config"
    export HOME="/root"
    
    bashio::log.info "Claude authentication persistence initialized"
}

# Install required tools
install_tools() {
    bashio::log.info "Installing additional tools..."
    if ! apk add --no-cache ttyd jq curl; then
        bashio::log.error "Failed to install required tools"
        exit 1
    fi
    bashio::log.info "Tools installed successfully"
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
        # Use transparent session management
        echo "/opt/scripts/auto-session-manager.sh"
    elif [ "$auto_launch_claude" = "true" ]; then
        # Original behavior: auto-launch Claude directly
        echo "clear && echo 'Welcome to Claude Terminal!' && echo '' && echo 'Starting Claude...' && sleep 1 && node \$(which claude)"
    else
        # Interactive session picker
        if [ -f /usr/local/bin/claude-session-picker ]; then
            echo "clear && /usr/local/bin/claude-session-picker"
        else
            # Fallback if session picker is missing
            bashio::log.warning "Session picker not found, falling back to auto-launch"
            echo "clear && echo 'Welcome to Claude Terminal!' && echo '' && echo 'Starting Claude...' && sleep 1 && node \$(which claude)"
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
    bashio::log.info "Environment variables:"
    bashio::log.info "ANTHROPIC_CONFIG_DIR=${ANTHROPIC_CONFIG_DIR}"
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
    
    # Run ttyd with improved configuration
    exec ttyd \
        --port "${port}" \
        --interface 0.0.0.0 \
        --writable \
        bash -c "$launch_command"
}

# Main execution
main() {
    bashio::log.info "Initializing Claude Terminal add-on..."
    
    init_environment
    install_tools
    setup_session_picker
    start_web_terminal
}

# Execute main function
main "$@"