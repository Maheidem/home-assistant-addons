ARG BUILD_FROM
FROM ${BUILD_FROM}

# Install packages in a single layer to minimize image size
RUN apk add --no-cache \
    nodejs \
    npm \
    bash \
    curl \
    nano \
    tmux \
    screen \
    && npm install -g @anthropic-ai/claude-code@latest \
    && npm cache clean --force

# Create directories for Claude configuration and set working directory
RUN mkdir -p /config/claude-config/.claude \
    && chmod 755 /config/claude-config \
    && chmod 755 /config/claude-config/.claude
WORKDIR /config

# Copy startup script and modular scripts
COPY run.sh /run.sh
COPY scripts/ /opt/scripts/
RUN chmod +x /run.sh \
    && chmod +x /opt/scripts/*.sh

# Use exec form for better signal handling
CMD ["/run.sh"]