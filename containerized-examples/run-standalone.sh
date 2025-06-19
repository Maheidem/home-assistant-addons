#!/bin/bash

# Standalone version without bashio dependencies
# For containerized HomeAssistant deployments

# Logging functions (replacing bashio)
log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') $1"
}

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $1" >&2
}

log_warning() {
    echo "[WARNING] $(date '+%Y-%m-%d %H:%M:%S') $1"
}

# Initialize credentials and environment
init_environment() {
    # Ensure claude-config directory exists with proper permissions
    mkdir -p /config/claude-config
    chmod 777 /config/claude-config

    # Create links between credential locations and our persistent directory
    mkdir -p /root/.config
    ln -sf /config/claude-config /root/.config/anthropic

    # Link the found credential files to our persistent directory
    if [ -f "/config/claude-config/.claude" ]; then
        ln -sf /config/claude-config/.claude /root/.claude
    fi
    if [ -f "/config/claude-config/.claude.json" ]; then
        ln -sf /config/claude-config/.claude.json /root/.claude.json
    fi

    # Set environment variables
    export CLAUDE_CREDENTIALS_DIRECTORY="/config/claude-config"
    export ANTHROPIC_CONFIG_DIR="/config/claude-config"
    export HOME="/root"
}

# Setup credential management scripts
setup_credential_scripts() {
    # Create credentials-manager script
    cat > /usr/local/bin/credentials-manager << 'EOF'
#!/bin/bash
mkdir -p /config/claude-config
save_credentials() {
    for location in "/root/.claude" "/root/.claude.json" "/root/.config/anthropic/credentials.json"; do
        if [ -f "$location" ]; then
            cp -f "$location" "/config/claude-config/$(basename "$location")"
            chmod 600 "/config/claude-config/$(basename "$location")"
        fi
    done
}
logout() {
    echo "Clearing all credentials..."
    rm -rf /config/claude-config/.claude* /root/.claude*
    rm -rf /root/.config/anthropic /config/claude-config/credentials.json
    echo "Credentials cleared. Please restart to re-authenticate."
}
case "$1" in
    save) save_credentials ;;
    logout) logout ;;
    *) save_credentials ;;
esac
EOF

    # Create credentials-service script
    cat > /usr/local/bin/credentials-service << 'EOF'
#!/bin/bash
sleep 5
while true; do
    /usr/local/bin/credentials-manager save > /dev/null 2>&1
    sleep 30
done
EOF

    # Create claude-auth script
    cat > /usr/local/bin/claude-auth << 'EOF'
#!/bin/bash
show_help() {
    echo "Claude Auth Tool - Manage Claude authentication"
    echo "Usage: claude-auth [debug|save|logout|help]"
}
debug_info() {
    echo "===== CLAUDE AUTH DEBUG ====="
    echo "Directory contents of /config/claude-config:"
    ls -la /config/claude-config/ 2>/dev/null || echo "Directory does not exist"
    echo "Environment variables:"
    echo "CLAUDE_CREDENTIALS_DIRECTORY=$CLAUDE_CREDENTIALS_DIRECTORY"
    echo "ANTHROPIC_CONFIG_DIR=$ANTHROPIC_CONFIG_DIR"
    echo "HOME=$HOME"
}
save_credentials() {
    /usr/local/bin/credentials-manager save
}
logout() {
    /usr/local/bin/credentials-manager logout
}
case "$1" in
    debug) debug_info ;;
    save) save_credentials ;;
    logout) logout ;;
    help|--help|-h) show_help ;;
    *) show_help ;;
esac
EOF
    
    # Make scripts executable
    chmod +x /usr/local/bin/credentials-manager
    chmod +x /usr/local/bin/credentials-service
    chmod +x /usr/local/bin/claude-auth

    # Create convenience aliases
    ln -sf /usr/local/bin/credentials-manager /usr/local/bin/claude-logout
    ln -sf /usr/local/bin/claude-auth /usr/local/bin/debug-claude-auth
    
    log_info "Credential management scripts installed successfully"
}

# Start credential monitoring service
start_credential_service() {
    log_info "Starting credential monitoring service..."
    /usr/local/bin/credentials-service &
    # Give the service a moment to start before proceeding
    sleep 2
}

# Start main web terminal
start_web_terminal() {
    local port=7681
    log_info "Starting web terminal on port ${port}..."
    
    # Log environment information for debugging
    log_info "Environment variables:"
    log_info "CLAUDE_CREDENTIALS_DIRECTORY=${CLAUDE_CREDENTIALS_DIRECTORY}"
    log_info "ANTHROPIC_CONFIG_DIR=${ANTHROPIC_CONFIG_DIR}"
    log_info "HOME=${HOME}"

    # Run ttyd with improved configuration
    exec ttyd \
        --port "${port}" \
        --interface 0.0.0.0 \
        --writable \
        bash -c "clear && echo 'Welcome to Claude Terminal (Standalone)!' && echo '' && echo 'To log out: run claude-logout' && echo '' && echo 'Starting Claude...' && sleep 1 && node \$(which claude) && /usr/local/bin/credentials-manager save"
}

# Main execution
main() {
    log_info "Initializing Claude Terminal (Standalone) for containerized HomeAssistant..."
    
    init_environment
    setup_credential_scripts
    start_credential_service
    start_web_terminal
}

# Execute main function
main "$@"