#!/bin/bash

# Claude Terminal Setup Script for Containerized HomeAssistant
# Usage: ./setup.sh [path-to-homeassistant-config]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HA_CONFIG_PATH="${1:-$(pwd)/config}"

echo "=== Claude Terminal Setup for Containerized HomeAssistant ==="
echo "HomeAssistant config path: $HA_CONFIG_PATH"

# Validate HomeAssistant config directory
if [ ! -d "$HA_CONFIG_PATH" ]; then
    echo "ERROR: HomeAssistant config directory not found: $HA_CONFIG_PATH"
    echo "Usage: $0 [path-to-homeassistant-config]"
    exit 1
fi

if [ ! -f "$HA_CONFIG_PATH/configuration.yaml" ]; then
    echo "WARNING: configuration.yaml not found in $HA_CONFIG_PATH"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Create claude-config directory
echo "Creating Claude configuration directory..."
mkdir -p "$HA_CONFIG_PATH/claude-config"
chmod 755 "$HA_CONFIG_PATH/claude-config"

# Copy necessary files
echo "Copying Claude Terminal files..."
cp "$SCRIPT_DIR/Dockerfile.standalone" ./ 2>/dev/null || echo "Dockerfile.standalone not found in current directory"
cp "$SCRIPT_DIR/run-standalone.sh" ./ 2>/dev/null || echo "run-standalone.sh not found in current directory"

# Make run script executable
chmod +x ./run-standalone.sh 2>/dev/null || true

# Build Docker image
echo "Building Claude Terminal Docker image..."
if [ -f "./Dockerfile.standalone" ]; then
    docker build -f Dockerfile.standalone -t claude-terminal-standalone .
    echo "✅ Docker image built successfully"
else
    echo "❌ Dockerfile.standalone not found. Please ensure all files are in the current directory."
    exit 1
fi

# Create docker run command
DOCKER_RUN_CMD="docker run -d \\
  --name claude-terminal \\
  -p 7681:7681 \\
  -v \"$HA_CONFIG_PATH:/config:rw\" \\
  -v claude-auth-data:/root/.config/anthropic \\
  --restart unless-stopped \\
  claude-terminal-standalone"

# Check if container already exists
if docker ps -a --format 'table {{.Names}}' | grep -q "^claude-terminal$"; then
    echo "Existing claude-terminal container found. Stopping and removing..."
    docker stop claude-terminal 2>/dev/null || true
    docker rm claude-terminal 2>/dev/null || true
fi

# Start the container
echo "Starting Claude Terminal container..."
eval $DOCKER_RUN_CMD

# Wait for container to start
sleep 3

# Check if container is running
if docker ps --format 'table {{.Names}}' | grep -q "^claude-terminal$"; then
    echo "✅ Claude Terminal started successfully!"
    echo ""
    echo "🌐 Access the terminal at: http://localhost:7681"
    echo "📁 HomeAssistant config mapped to: /config"
    echo "🔑 Credentials stored in: claude-auth-data volume"
    echo ""
    echo "Available commands:"
    echo "  docker logs claude-terminal     # View logs"
    echo "  docker stop claude-terminal     # Stop container"
    echo "  docker start claude-terminal    # Start container"
    echo "  docker exec -it claude-terminal bash  # Access container shell"
else
    echo "❌ Failed to start Claude Terminal container"
    echo "Check logs with: docker logs claude-terminal"
    exit 1
fi

echo ""
echo "🎉 Setup complete! Open http://localhost:7681 to access Claude Terminal."