#!/bin/bash

# Auto Session Manager - Transparently manage persistent terminal sessions
# Automatically creates/resumes tmux sessions for seamless user experience

SESSION_NAME="claude-main"
LOG_PREFIX="session-manager"

log_info() {
    echo "[$LOG_PREFIX] $1"
}

# Check if tmux session exists
session_exists() {
    tmux has-session -t "$SESSION_NAME" 2>/dev/null
}

# Create new tmux session with Claude
create_new_session() {
    log_info "Creating new persistent session: $SESSION_NAME"

    # Create new tmux session running Claude directly
    tmux new-session -d -s "$SESSION_NAME" -c /config claude
}

# Resume existing tmux session - just attach, no key injection
resume_session() {
    log_info "Resuming existing session: $SESSION_NAME"
}

# Main session management logic
main() {
    if session_exists; then
        resume_session
    else
        create_new_session
    fi

    # Attach to session (new or existing)
    exec tmux attach-session -t "$SESSION_NAME"
}

# Handle cleanup on exit
cleanup() {
    log_info "Session manager stopping..."
    exit 0
}

trap cleanup EXIT INT TERM

# Run main function
main "$@"
