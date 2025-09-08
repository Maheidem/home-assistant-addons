#!/bin/bash

# Credential Monitor - Continuously backup Claude authentication files
# This script runs in the background to ensure all Claude auth data is persisted

WATCH_DIRS="/root/.claude /root"
BACKUP_DIR="/config/claude-config"
LOG_PREFIX="credential-monitor"

log_info() {
    echo "[$LOG_PREFIX] $1"
}

log_error() {
    echo "[$LOG_PREFIX] ERROR: $1" >&2
}

# Backup a file if it exists and has changed
backup_file() {
    local src_file="$1"
    local dest_file="$2"
    
    if [ -f "$src_file" ]; then
        # Create destination directory if needed
        local dest_dir=$(dirname "$dest_file")
        mkdir -p "$dest_dir"
        
        # Check if file has changed or doesn't exist in backup
        if [ ! -f "$dest_file" ] || ! cmp -s "$src_file" "$dest_file"; then
            if cp "$src_file" "$dest_file" 2>/dev/null; then
                chmod 600 "$dest_file"
                log_info "Backed up: $src_file -> $dest_file"
            else
                log_error "Failed to backup: $src_file"
            fi
        fi
    fi
}

# Backup a directory recursively
backup_directory() {
    local src_dir="$1"
    local dest_dir="$2"
    
    if [ -d "$src_dir" ]; then
        # Create destination directory
        mkdir -p "$dest_dir"
        
        # Copy all files, preserving structure
        find "$src_dir" -type f | while read -r file; do
            relative_path="${file#$src_dir/}"
            dest_file="$dest_dir/$relative_path"
            backup_file "$file" "$dest_file"
        done
    fi
}

# Monitor and backup Claude files
monitor_credentials() {
    log_info "Starting credential monitoring..."
    
    while true; do
        # Backup main Claude config file
        backup_file "/root/.claude.json" "$BACKUP_DIR/.claude.json"
        
        # Backup entire .claude directory
        backup_directory "/root/.claude" "$BACKUP_DIR/.claude"
        
        # Backup any other potential auth files
        for auth_file in "/root/.config/anthropic/session_key" "/root/.config/anthropic/client.json"; do
            if [ -f "$auth_file" ]; then
                filename=$(basename "$auth_file")
                backup_file "$auth_file" "$BACKUP_DIR/$filename"
            fi
        done
        
        # Wait before next check (5 seconds)
        sleep 5
    done
}

# Handle cleanup on exit
cleanup() {
    log_info "Credential monitor stopping..."
    exit 0
}

trap cleanup EXIT INT TERM

# Start monitoring
monitor_credentials