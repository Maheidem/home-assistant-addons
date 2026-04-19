ARG BUILD_FROM
FROM ${BUILD_FROM}

# Use HA's Debian (glibc) base. Alpine's musl does NOT export `posix_getdents`
# which Claude Code's native installer requires starting at 2.1.64+. Debian's
# glibc ships the symbol, so the official native installer works out of the box.
# https://code.claude.com/docs/en/setup

ENV DEBIAN_FRONTEND=noninteractive

# --- GitHub CLI apt repo --------------------------------------------------
# The `gh` package isn't in Debian's main repos; use GitHub's official one.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl gnupg \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
       > /etc/apt/sources.list.d/github-cli.list

# --- Core packages --------------------------------------------------------
# - git, nano, tmux, tree: core tools
# - jq: JSON processing
# - nodejs, npm: general-purpose Node runtime (not needed for Claude itself
#   anymore, kept for user dev work)
# - ripgrep: system ripgrep (USE_BUILTIN_RIPGREP=0 below)
# - gh: GitHub PRs/issues/workflows
# - openssh-client: SSH for git operations
# - python3: HA automations and scripting
# - unzip: needed to unpack the Bun installer archive
# - bash-completion, less: creature-comforts
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash-completion \
        gh \
        git \
        jq \
        less \
        nano \
        nodejs \
        npm \
        openssh-client \
        python3 \
        ripgrep \
        tmux \
        tree \
        unzip \
    && rm -rf /var/lib/apt/lists/*

# --- ttyd (web terminal) --------------------------------------------------
# Not in Debian repos; use the upstream static binary.
ARG TTYD_VERSION=1.7.7
RUN arch="$(uname -m)" \
    && curl -fsSL -o /usr/local/bin/ttyd "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.${arch}" \
    && chmod +x /usr/local/bin/ttyd \
    && ttyd --version

# --- yq (Go version) -----------------------------------------------------
# Debian ships a Python yq; we use mikefarah's Go yq for YAML round-tripping.
ARG YQ_VERSION=v4.44.5
RUN arch="$(dpkg --print-architecture)" \
    && curl -fsSL -o /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${arch}" \
    && chmod +x /usr/local/bin/yq \
    && yq --version

# --- Claude Code CLI ------------------------------------------------------
# Official native installer. Works on glibc distros (Debian). Pinned version.
# Auto-updates are disabled via DISABLE_AUTOUPDATER in default settings; the
# image is the unit of update.
ENV CLAUDE_VERSION=2.1.89
RUN curl -fsSL https://claude.ai/install.sh | bash -s "${CLAUDE_VERSION}" \
    && /root/.local/bin/claude --version

# --- Bun ------------------------------------------------------------------
# Required by Bun-based plugin runtimes (e.g. the Telegram channel plugin).
# BUN_INSTALL=/usr/local lands the binary at /usr/local/bin/bun (on PATH).
ENV BUN_VERSION=1.3.12
ENV BUN_INSTALL=/usr/local
RUN curl -fsSL https://bun.sh/install | bash -s "bun-v${BUN_VERSION}" \
    && /usr/local/bin/bun --version

# Make the native-installed Claude binary available on every shell's PATH.
ENV PATH="/root/.local/bin:${PATH}"

# --- Default settings ----------------------------------------------------
# run.sh copies this into the persistent volume on first boot if absent.
# - USE_BUILTIN_RIPGREP=0 → use system ripgrep
# - DISABLE_AUTOUPDATER=1 → image is the update unit; rebuilds bump versions
RUN mkdir -p /opt/claude-defaults \
    && printf '%s\n' \
       '{' \
       '  "env": {' \
       '    "USE_BUILTIN_RIPGREP": "0",' \
       '    "DISABLE_AUTOUPDATER": "1"' \
       '  }' \
       '}' > /opt/claude-defaults/settings.json

WORKDIR /config

# --- Boot scripts and shell config ---------------------------------------
# bashrc.sh is loaded by every interactive shell via /etc/profile.d/.
COPY run.sh /run.sh
COPY tmux-session.sh /opt/tmux-session.sh
COPY tmux.conf /root/.tmux.conf
COPY bashrc.sh /etc/profile.d/02-claude-terminal-bash.sh
RUN chmod +x /run.sh /opt/tmux-session.sh

# Use exec form for better signal handling.
CMD ["/run.sh"]
