ARG BUILD_FROM
FROM ${BUILD_FROM}

# Using HA's Debian (glibc) base rather than Alpine. The official OpenCode
# image (ghcr.io/anomalyco/opencode) IS Alpine-musl-based, but:
#   1. We still need bashio + s6-overlay for the HA supervisor lifecycle,
#      which only come pre-installed in the HA base images.
#   2. Bun-compiled binaries from the Alpine image are not guaranteed to be
#      statically linked, so grafting the binary onto Debian is risky.
# Installing via the official curl installer on Debian produces a host-native
# (glibc) binary — simpler, and mirrors claude-terminal's proven approach.

ENV DEBIAN_FRONTEND=noninteractive

# --- GitHub CLI apt repo --------------------------------------------------
# `gh` isn't in Debian's main repo; pull from GitHub's official one.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl gnupg \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
       > /etc/apt/sources.list.d/github-cli.list

# --- Core packages --------------------------------------------------------
# - git, nano, tree: core tools
# - jq: reading HA options, seeding opencode.json
# - nodejs, npm: required by local MCP servers that OpenCode spawns via `npx`
#   (examples from the maintainer's live config: linkedin-mcp, nano-banana,
#   waha-whatsapp — all run through npx)
# - ripgrep: fast search used by OpenCode's `grep` tool
# - gh: GitHub PRs/issues (complements `opencode pr`)
# - openssh-client: git over SSH for push/pull
# - python3: scripting, HA automations
# - unzip: needed by Bun's installer
# - bash-completion, less: creature-comforts for the rare interactive shell
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
        tree \
        unzip \
    && rm -rf /var/lib/apt/lists/*

# --- Bun ------------------------------------------------------------------
# Required by some OpenCode plugins and by Bun-based MCP runtimes. Installing
# to /usr/local lands the binary at /usr/local/bin/bun (already on PATH).
ENV BUN_VERSION=1.3.12
ENV BUN_INSTALL=/usr/local
RUN curl -fsSL https://bun.sh/install | bash -s "bun-v${BUN_VERSION}" \
    && /usr/local/bin/bun --version

# --- OpenCode -------------------------------------------------------------
# Official installer from https://opencode.ai/install. Always writes the
# binary to $HOME/.opencode/bin/opencode (INSTALL_DIR is hard-coded in the
# script, not env-var configurable). We symlink it into /usr/local/bin so
# it's reachable regardless of $HOME. OpenCode is a single self-contained
# Bun binary; bumping OPENCODE_VERSION + rebuilding the image is the
# upgrade path.
ENV OPENCODE_VERSION=1.14.22
RUN curl -fsSL https://opencode.ai/install | bash -s -- --version "${OPENCODE_VERSION}" \
    && ln -sf /root/.opencode/bin/opencode /usr/local/bin/opencode \
    && /usr/local/bin/opencode --version

# Make sure user-installed CLIs land on PATH for interactive shells.
ENV PATH="/root/.local/bin:/usr/local/bin:${PATH}"

WORKDIR /config

# --- Boot scripts and shell config ---------------------------------------
COPY run.sh /run.sh
COPY opencode-boot.sh /opt/opencode-boot.sh
COPY bashrc.sh /etc/profile.d/02-opencode-terminal-bash.sh
RUN chmod +x /run.sh /opt/opencode-boot.sh

# exec form so signals (SIGTERM from HA supervisor) propagate cleanly.
CMD ["/run.sh"]
