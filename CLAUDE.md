# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Home Assistant add-on repository. The sole add-on is **Claude Terminal** (`claude-terminal/`): an Alpine container that exposes the Claude Code CLI via a `ttyd` web terminal, mounted into the HA dashboard via ingress.

## Development Environment

`nix develop` (or `direnv allow`) drops you into a shell with `podman`, `hadolint`, `jq`, `yq-go`, and aliases defined in `flake.nix`:

- `build-addon` — podman build of the amd64 image
- `run-addon` — run locally on `:7681` with `./config` mounted
- `lint-dockerfile` — hadolint
- `test-endpoint` — curl `localhost:7681`

Full hot-reload, multi-port, and debugging recipes live in `DEVELOPMENT.md`.

## Architecture

### Persistence model

`run.sh` sets a single environment variable:

```bash
export CLAUDE_CONFIG_DIR=/config/claude-config
```

This is the **official** knob ([env-vars docs](https://code.claude.com/docs/en/env-vars)) for relocating Claude Code state. Claude Code itself honours it for auth, MCP config, conversation history, agents, skills, hooks, commands, etc. — everything lands under that directory, on the persistent HA `/config` volume.

### Symlinks still needed

The env var only affects Claude Code's own process. Plugins, channels, and other out-of-process helpers (e.g. the bun-based Telegram channel) use the literal `$HOME/.claude/` path and do **not** honour `CLAUDE_CONFIG_DIR`. Similarly, SSH keys, `.gitconfig`, GitHub CLI auth, and shell history are not Claude Code's problem at all, but they're "config the user set up" and should persist too. `run.sh` symlinks five paths into the persistent volume:

| Symlink | Target |
|---|---|
| `/root/.claude` | `/config/claude-config` (same dir `CLAUDE_CONFIG_DIR` points at — makes plugin/channel state persist regardless of whether they honour the env var) |
| `/root/.ssh` | `/config/claude-config/ssh` (chmod 700, files 600) |
| `/root/.gitconfig` | `/config/claude-config/gitconfig` |
| `/root/.config/gh` | `/config/claude-config/config-gh` |
| `/root/.bash_history` | `/config/claude-config/bash_history` |

The `/root/.claude` symlink is deliberately redundant with `CLAUDE_CONFIG_DIR`: when both are in place, Claude Code, plugins, and channels all converge on the same persistent directory, whatever code path they use to discover it.

Claude's native installer directory (`/root/.local/share/claude/versions/`) is also symlinked, into `/config/claude-config/claude-installations/`, so manual `claude install X` and auto-updates persist across add-on restarts. On every boot, `run.sh` re-points `/root/.local/bin/claude` at the newest installed version.

### Launch flow

`run.sh` does, in order:

1. `mkdir -p /config/claude-config && chmod 700`
2. Seed default `settings.json` on first boot (`USE_BUILTIN_RIPGREP=0`, `DISABLE_AUTOUPDATER=1`)
3. Export `CLAUDE_CONFIG_DIR` and read the `startup_command` add-on option into env
4. Write `/etc/profile.d/01-claude-terminal-welcome.sh` (idempotent first-prompt banner)
5. **Start tmux *detached* at container boot**: `tmux new-session -d -s claude-main -c /config /opt/tmux-session.sh`
6. `exec ttyd ... bash -lc 'tmux new-session -A -s claude-main -c /config /opt/tmux-session.sh'`

The detached tmux at step 5 is the **always-on inversion**: whatever the user puts in `startup_command` (e.g. `claude -c --channels plugin:telegram@claude-plugins-official`) starts at container boot regardless of whether anyone has opened the web terminal. ttyd attaches the browser to the already-running session.

### `tmux-session.sh`

Tiny wrapper run inside the tmux session on first creation. Reads `STARTUP_CMD` from env (set by `run.sh` from the `startup_command` config option). If non-empty, runs it via `bash -lc "$STARTUP_CMD"` then drops to `exec bash -l` so the user can recover via the web terminal if the command exits. If empty, just `exec bash -l`.

The command is passed via env, **not** interpolated into the tmux command line — this avoids quoting hell when the value contains quotes, spaces, or shell metacharacters.

### `startup_command` option

Single user-tunable knob in `config.yaml`. Examples:

| Value | Effect |
|---|---|
| `""` (default) | Plain bash. User types `claude` themselves. |
| `claude` | Auto-launch Claude on boot. |
| `claude -c` | Resume most recent conversation on boot. |
| `claude -c --channels plugin:telegram@claude-plugins-official` | Always-on Telegram bot. |

### Container build constraints (Alpine musl)

- Claude Code is installed via the **official native installer**: `curl -fsSL https://claude.ai/install.sh | bash -s ${CLAUDE_VERSION}`. This is the canonical install path per [Anthropic's setup docs](https://code.claude.com/docs/en/setup). The binary lands at `/root/.local/bin/claude`. System `ripgrep` plus `USE_BUILTIN_RIPGREP=0` in default `settings.json` keeps Claude off its bundled ripgrep.
- The add-on uses the **Debian (glibc) HA base image** (`ghcr.io/home-assistant/{arch}-base-debian:bookworm`) rather than the Alpine base. Reason: Claude Code's native installer starting at 2.1.64+ produces a binary that references `posix_getdents`, a musl symbol Alpine (still on 1.2.5 as of 2026-04) does not export, causing the binary to fail to relocate at runtime. Debian's glibc ships the symbol, so the native installer "just works." Anthropic's docs claim Alpine 3.19+ is supported; empirical testing shows that claim is broken for current releases — do not revert to the Alpine base without re-verifying.
- Claude Code version is pinned in the Dockerfile via `ENV CLAUDE_VERSION=...`. Bump deliberately.
- Auto-update is disabled inside the container (`DISABLE_AUTOUPDATER=1`) — image rebuilds are the unit of update.
- **Bun** is installed via Bun's official installer (not in Alpine repos). Required by Bun-based plugin runtimes such as the official Telegram channel.
- Multi-arch: `amd64` and `aarch64` only. armv7 was dropped because Bun does not ship a musl build for it.

### Key environment variables

- `CLAUDE_CONFIG_DIR=/config/claude-config` — single source of truth for Claude Code state
- `HOME=/root`
- `STARTUP_CMD` — set by run.sh from the `startup_command` add-on option, read by `tmux-session.sh`
- `BUN_INSTALL=/usr/local` and `PATH` includes `/usr/local/bin` and `/root/.local/bin`

## File Conventions

- Shell scripts use `#!/usr/bin/with-contenv bashio` (when they need bashio helpers) or `#!/bin/bash` (for plain wrappers like `tmux-session.sh`); they use `bashio::log.*` for logging when bashio is available.
- YAML: 2-space indent. Shell: 4-space indent.
- Auth files require `chmod 600`; persistent state directory `/config/claude-config` is `chmod 700`.

## Notes on other docs

- `DEVELOPMENT.md` — current dev workflow.
- `claude-terminal/CHANGELOG.md` — user-facing release notes; bump alongside `config.yaml:version`.
- `claude-terminal/DOCS.md` — what the user sees in the HA add-on store.
- `PLAN.md` (repo root) — v2 implementation plan; once 2.0.0 ships, archive or delete.
