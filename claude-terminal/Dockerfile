ARG BUILD_FROM
FROM ${BUILD_FROM}

# Install system packages
# - bash, curl, git, nano, tmux: core tools
# - ttyd, jq: web terminal and JSON processing
# - nodejs, npm: required for Claude Code CLI
# - ripgrep: required by Claude Code for search
# - github-cli: GitHub PRs, issues, workflows
# - openssh-client: SSH for git operations
# - python3: HA automations and scripting
# - yq-go: YAML processor for HA configs
# - tree: directory visualization
RUN apk add --no-cache \
    bash \
    curl \
    git \
    github-cli \
    jq \
    nano \
    nodejs \
    npm \
    openssh-client \
    python3 \
    ripgrep \
    tmux \
    tree \
    ttyd \
    yq-go

# Install Claude Code CLI with pinned version for reproducible builds
# NOTE: Native installer (curl -fsSL https://claude.ai/install.sh | bash) is preferred
# but currently broken on Alpine musl (posix_getdents symbol not found).
# Revisit when Anthropic fixes the musl build.
RUN npm install -g @anthropic-ai/claude-code@2.1.63

# Stage default settings to a build-time location
# run.sh will copy these into the persistent volume at runtime if not already present
# USE_BUILTIN_RIPGREP=0 required on Alpine musl (use system ripgrep instead)
RUN mkdir -p /root/.claude /opt/claude-defaults \
    && echo '{"env":{"USE_BUILTIN_RIPGREP":"0"}}' > /opt/claude-defaults/settings.json

WORKDIR /config

# Copy startup script, modular scripts, and tmux configuration
COPY run.sh /run.sh
COPY scripts/ /opt/scripts/
COPY tmux.conf /root/.tmux.conf
RUN chmod +x /run.sh \
    && chmod +x /opt/scripts/*.sh

# Use exec form for better signal handling
CMD ["/run.sh"]
