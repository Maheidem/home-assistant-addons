# Claude Terminal for Containerized HomeAssistant

This directory contains examples and instructions for integrating Claude Terminal with containerized HomeAssistant setups (non-HASS OS).

## Quick Start

### Option 1: Docker Compose Integration (Recommended)

1. **Copy the files to your HomeAssistant directory:**
   ```bash
   # Navigate to your HomeAssistant directory (where your config folder is)
   cd /path/to/your/homeassistant
   
   # Copy the standalone files
   wget https://raw.githubusercontent.com/heytcass/home-assistant-addons/main/containerized-examples/Dockerfile.standalone
   wget https://raw.githubusercontent.com/heytcass/home-assistant-addons/main/containerized-examples/run-standalone.sh
   wget https://raw.githubusercontent.com/heytcass/home-assistant-addons/main/containerized-examples/docker-compose.yaml
   ```

2. **Update your docker-compose.yaml:**
   Add the claude-terminal service to your existing docker-compose.yaml or use the provided example.

3. **Build and start:**
   ```bash
   docker-compose up -d claude-terminal
   ```

4. **Access the terminal:**
   Open `http://your-host:7681` in your browser.

### Option 2: Standalone Docker Container

1. **Build the container:**
   ```bash
   git clone https://github.com/heytcass/home-assistant-addons.git
   cd home-assistant-addons/containerized-examples
   docker build -f Dockerfile.standalone -t claude-terminal-standalone .
   ```

2. **Run the container:**
   ```bash
   docker run -d \
     --name claude-terminal \
     -p 7681:7681 \
     -v /path/to/your/homeassistant/config:/config:rw \
     -v claude-auth-data:/root/.config/anthropic \
     claude-terminal-standalone
   ```

3. **Access the terminal:**
   Open `http://your-host:7681` in your browser.

## Configuration

### Volume Mapping
- `/config` - Maps to your HomeAssistant config directory
- `/root/.config/anthropic` - Persistent storage for Claude credentials

### Authentication
- First access will prompt for Anthropic OAuth login
- Credentials are automatically persisted across container restarts
- Use `claude-logout` command to clear authentication

### Available Commands
- `claude` - Start Claude Code CLI
- `claude-logout` - Clear authentication and logout
- `claude-auth debug` - Show authentication debug information

## Integration with HomeAssistant

### Accessing HomeAssistant Files
The Claude Terminal has full access to your HomeAssistant configuration directory:
```bash
# Navigate to HomeAssistant config
cd /config

# Edit configuration.yaml
claude edit configuration.yaml

# Work with automations
claude analyze automations.yaml
```

### Custom Automations
You can create automations that trigger Claude Terminal actions or use Claude to help develop new automations.

## Differences from HASS OS Add-on

| Feature | HASS OS Add-on | Containerized Version |
|---------|----------------|----------------------|
| Installation | Add-on store | Manual Docker setup |
| UI Integration | HA sidebar panel | Separate web interface |
| Port Management | Automatic ingress | Manual port mapping |
| Logging | bashio integration | Standard console logs |
| Updates | Automatic | Manual container updates |

## Troubleshooting

### Container won't start
```bash
# Check logs
docker logs claude-terminal

# Check if port is already in use
netstat -tulpn | grep 7681
```

### Authentication issues
```bash
# Access container shell
docker exec -it claude-terminal bash

# Run debug command
claude-auth debug

# Clear and re-authenticate
claude-logout
```

### Configuration problems
```bash
# Verify volume mounts
docker inspect claude-terminal

# Check directory permissions
ls -la /config/claude-config
```

## Security Considerations

- The container runs with access to your HomeAssistant config directory
- Claude credentials are stored in persistent volumes
- Web interface is exposed on the configured port (default 7681)
- Consider using a reverse proxy with authentication for external access

## Advanced Usage

### Custom Environment Variables
```yaml
environment:
  - CLAUDE_CREDENTIALS_DIRECTORY=/config/claude-config
  - ANTHROPIC_CONFIG_DIR=/config/claude-config
  - CUSTOM_VAR=value
```

### Network Configuration
```yaml
networks:
  homeassistant:
    external: true
```

### Resource Limits
```yaml
deploy:
  resources:
    limits:
      memory: 512M
      cpus: '0.5'
```

## Support

For issues specific to the containerized version, please open an issue in the [home-assistant-addons repository](https://github.com/heytcass/home-assistant-addons/issues).

For Claude Code CLI issues, refer to the [official documentation](https://github.com/anthropics/claude-code).