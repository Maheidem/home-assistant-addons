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
    
    # Create new tmux session in detached mode
    tmux new-session -d -s "$SESSION_NAME" -c /config
    
    # Send welcome message and start Claude
    tmux send-keys -t "$SESSION_NAME" "clear" Enter
    tmux send-keys -t "$SESSION_NAME" "echo '🤖 Claude Terminal - Persistent Session'" Enter
    tmux send-keys -t "$SESSION_NAME" "echo 'Your session will persist when you close the browser!'" Enter
    tmux send-keys -t "$SESSION_NAME" "echo ''" Enter
    tmux send-keys -t "$SESSION_NAME" "echo 'Starting Claude...'" Enter
    tmux send-keys -t "$SESSION_NAME" "sleep 2 && node \$(which claude)" Enter
}

# Resume existing tmux session
resume_session() {
    log_info "Resuming existing session: $SESSION_NAME"
    
    # Send a notification that user has reconnected
    tmux send-keys -t "$SESSION_NAME" "" # Just refresh the prompt
    tmux send-keys -t "$SESSION_NAME" "echo ''" Enter
    tmux send-keys -t "$SESSION_NAME" "echo '👋 Welcome back! Session resumed.'" Enter
}

# Main session management logic
main() {
    # Wait a moment for tmux to be ready
    sleep 1
    
    if session_exists; then
        resume_session
        # Attach to existing session
        exec tmux attach-session -t "$SESSION_NAME"
    else
        create_new_session
        # Attach to new session
        exec tmux attach-session -t "$SESSION_NAME"
    fi
}

# Handle cleanup on exit
cleanup() {
    log_info "Session manager stopping..."
    exit 0
}

trap cleanup EXIT INT TERM

# Run main function
main "$@"