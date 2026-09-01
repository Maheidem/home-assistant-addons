ARG BUILD_FROM
FROM ${BUILD_FROM}

# Use HA's Debian (glibc) base. Alpine's musl does NOT export `posix_getdents`
# which Claude Code's native installer requires starting at 2.1.64+. Debian's
# glibc ships the symbol, so the official native installer works out of the box.
# https://code.claude.com/docs/en/setup

ENV DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# --- GitHub CLI apt repo --------------------------------------------------
# The `gh` package isn't in Debian's main repos; use GitHub's official one.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl gnupg \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
       > /etc/apt/sources.list.d/github-cli.list \
    && rm -rf /var/lib/apt/lists/*

# --- Core packages --------------------------------------------------------
# - git, nano, tmux, tree: core tools
# - jq: JSON processing (also used by run.sh and the ha-* helpers)
# - nodejs, npm: general-purpose Node runtime (not needed for Claude itself
#   anymore, kept for user dev work). Bookworm ships Node 18, which reached
#   upstream EOL in April 2025; users who need a current Node should install
#   one under /config via nvm/fnm, or use bun instead.
# - ripgrep: system ripgrep (USE_BUILTIN_RIPGREP=0 in the default settings)
# - gh: GitHub PRs/issues/workflows
# - openssh-client: SSH for git operations
# - python3: HA automations and scripting
# - qrencode: `claude-login` renders the OAuth URL as a terminal QR code
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
        qrencode \
        ripgrep \
        tmux \
        tree \
        unzip \
    && rm -rf /var/lib/apt/lists/*

# --- ttyd (web terminal) --------------------------------------------------
# Not in Debian repos; use the upstream static binary, verified against the
# SHA256SUMS file published with the same release so a tampered or truncated
# download fails the build instead of shipping.
ARG TTYD_VERSION=1.7.7
RUN arch="$(uname -m)" \
    && base="https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}" \
    && curl -fsSL -o /tmp/ttyd "${base}/ttyd.${arch}" \
    && curl -fsSL -o /tmp/SHA256SUMS "${base}/SHA256SUMS" \
    && awk -v f="ttyd.${arch}" '$2 == f { print $1 "  /tmp/ttyd" }' /tmp/SHA256SUMS > /tmp/ttyd.sha256 \
    && test -s /tmp/ttyd.sha256 \
    && sha256sum -c /tmp/ttyd.sha256 \
    && install -m 0755 /tmp/ttyd /usr/local/bin/ttyd \
    && rm -f /tmp/ttyd /tmp/SHA256SUMS /tmp/ttyd.sha256 \
    && ttyd --version

# --- Claude Code CLI ------------------------------------------------------
# Official native installer. Works on glibc distros (Debian). Pinned version
# is only the *starting point* — run.sh persists the install dir and
# re-points the launcher on every boot, so Claude's own auto-updater and
# `claude install X` both stick across restarts. See run.sh for the details.
# The trailing rm: `claude --version` may leave state under /root/.claude and
# /root/.config; run.sh symlinks those paths to the persistent volume on every
# boot and would otherwise stash the image's leftovers into migrated/ each
# time. /root/.claude.json is deliberately KEPT: the installer records
# `installMethod: native` there, and without it `claude doctor` / `claude
# update` warn that the install method is "not set" on every fresh volume.
ENV CLAUDE_VERSION=2.1.257
RUN curl -fsSL https://claude.ai/install.sh | bash -s "${CLAUDE_VERSION}" \
    && /root/.local/bin/claude --version \
    && rm -rf /root/.claude /root/.config

# --- Bun ------------------------------------------------------------------
# Required by Bun-based plugin runtimes (e.g. the Telegram channel plugin).
# BUN_INSTALL=/usr/local lands the binary at /usr/local/bin/bun (on PATH).
ENV BUN_VERSION=1.4.0
ENV BUN_INSTALL=/usr/local
RUN curl -fsSL https://bun.sh/install | bash -s "bun-v${BUN_VERSION}" \
    && /usr/local/bin/bun --version

# Make the native-installed Claude binary available on every shell's PATH.
ENV PATH="/root/.local/bin:${PATH}"

# --- Defaults seeded into the persistent volume on first boot ------------
# settings.json: system ripgrep + permission deny rules for secrets.yaml,
# .storage and the recorder DB. CLAUDE.md: project instructions for /config.
# run.sh copies each only if the destination doesn't exist yet.
COPY settings.default.json /opt/claude-defaults/settings.json
COPY config-CLAUDE.md /opt/claude-defaults/CLAUDE.md

WORKDIR /config

# --- Boot scripts, shell config, helpers ----------------------------------
# welcome.sh and bashrc.sh are loaded by every interactive shell via
# /etc/profile.d/. bin/* are user-facing helpers (ha-check, ha-restart,
# ha-notify, claude-login).
COPY run.sh /run.sh
COPY tmux-session.sh /opt/tmux-session.sh
COPY tmux.conf /root/.tmux.conf
COPY welcome.sh /etc/profile.d/01-claude-terminal-welcome.sh
COPY bashrc.sh /etc/profile.d/02-claude-terminal-bash.sh
COPY bin/claude-login bin/ha-check bin/ha-restart bin/ha-notify /usr/local/bin/
RUN chmod +x /run.sh /opt/tmux-session.sh \
        /usr/local/bin/claude-login /usr/local/bin/ha-check \
        /usr/local/bin/ha-restart /usr/local/bin/ha-notify

# Use exec form for better signal handling.
CMD ["/run.sh"]
