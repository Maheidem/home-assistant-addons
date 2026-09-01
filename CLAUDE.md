# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Home Assistant add-on repository. The main add-on is **Claude Terminal** (`claude-terminal/`): a Debian container that exposes the Claude Code CLI via a `ttyd` web terminal, mounted into the HA dashboard via ingress. (`opencode-terminal/` is a separate, independent add-on.)

## Development Environment

`nix develop` (or `direnv allow`) drops you into a shell with `podman`, `hadolint`, `jq`, and aliases defined in `flake.nix`:

- `build-addon` — podman build of the amd64 image
- `run-addon` — run locally on `:7681` with `./config` mounted
- `build-addon-arm64` / `run-addon-arm64` — same with the aarch64 base image (what an Apple Silicon host can build natively)
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

The env var only affects Claude Code's own process. Plugins, channels, and other out-of-process helpers (e.g. the bun-based Telegram channel) use the literal `$HOME/.claude/` path and do **not** honour `CLAUDE_CONFIG_DIR`. Similarly, SSH keys, `.gitconfig`, GitHub CLI auth, and shell history are not Claude Code's problem at all, but they're "config the user set up" and should persist too. `run.sh` symlinks six paths into the persistent volume:

| Symlink | Target |
|---|---|
| `/root/.claude` | `/config/claude-config` (same dir `CLAUDE_CONFIG_DIR` points at — makes plugin/channel state persist regardless of whether they honour the env var) |
| `/root/.ssh` | `/config/claude-config/ssh` (chmod 700, files 600) |
| `/root/.gitconfig` | `/config/claude-config/gitconfig` |
| `/root/.config` | `/config/claude-config/dot-config` (wholesale — covers gh, npm, aws, gcloud, fly, etc.) |
| `/root/.bash_history` | `/config/claude-config/bash_history` |
| `/root/.local/share/claude` | `/config/claude-config/claude-installations` (so `claude install X` and auto-updates stick; `run.sh` also re-points `/root/.local/bin/claude` at the pinned (`claude_version`) or newest installed version on every boot, via a symlink target lexically under `/root/.local/share/claude/versions/` — required for Claude Code >= 2.1.207 to recognize the launcher as self-managed — and prunes everything but the newest two plus the active one) |

The `/root/.claude` symlink is deliberately redundant with `CLAUDE_CONFIG_DIR`: when both are in place, Claude Code, plugins, and channels all converge on the same persistent directory, whatever code path they use to discover it. The `/root/.config` symlink was broadened from a gh-only version in 2.0.3; `run.sh` one-time-migrates `/config/claude-config/config-gh/` → `/config/claude-config/dot-config/gh/` to preserve existing GitHub CLI auth.

`ensure_symlink` never `rm -rf`s a non-empty real file/dir that is in the way: it moves it to `/config/claude-config/migrated/<name>.<epoch>` and logs a warning (empty ones are removed). Because that check runs against the image's filesystem on every boot, the Dockerfile deletes `/root/.claude`, `/root/.claude.json` and `/root/.config` after the installer's `claude --version`, so there is never anything to stash.

### User customization hooks

Three optional files under `/config/claude-config/` let users tune their environment without modifying anything inside the container (which would be lost on restart):

| File | Loaded by | Purpose |
|---|---|---|
| `bashrc.local` | `/etc/profile.d/02-claude-terminal-bash.sh` | shell aliases, exports, PS1 overrides |
| `tmux.conf.local` | `/root/.tmux.conf` via `source-file` | tmux overrides |
| `init.sh` | `run.sh`, in a subshell | arbitrary boot-time shell (custom symlinks, background helpers, etc.) |

`init.sh` runs in a subshell so an `exit` inside the hook can't kill the boot; the tradeoff is that exports inside init.sh don't propagate to run.sh or the rest of the container — use `bashrc.local` for exports instead. Failures are logged but non-fatal so a broken hook can't block the container from starting.

The same applies to every other non-critical boot step in `run.sh` (seeding, install persistence, activation, pruning, symlinks, gh migration, session log dir): each is a function called as `step || bashio::log.warning ...`. That `||` suspends `set -e` inside the function, so each function chains its own critical commands with `&&`/`return` rather than relying on `-e`. Only the persistent dir, the env exports and the tmux start may abort the boot.

Two more files are seeded on first boot only (never overwritten): `/config/claude-config/settings.json` from `settings.default.json` (system ripgrep + `permissions.deny` for `//config/secrets.yaml`, `//config/.storage/**`, `//config/*.db`, `//config/*.db-*`) and `/config/CLAUDE.md` from `config-CLAUDE.md` (guidance for Claude working in a live HA config dir; describes the helpers).

### Launch flow

`run.sh` does, in order:

1. `mkdir -p /config/claude-config && chmod 700`
2. Seed `settings.json` and `/config/CLAUDE.md` on first boot
3. Persist the Claude install dir; activate `claude_version` (pin; also exports `DISABLE_AUTOUPDATER=1`) or the newest version; prune old versions
4. Symlink auxiliary user state (see table above)
5. Export env: `CLAUDE_CONFIG_DIR`, `CLAUDE_CODE_OAUTH_TOKEN` / `ANTHROPIC_API_KEY` from the `oauth_token` / `api_key` options (values only ever in env, never on a command line; both set → warning that `ANTHROPIC_API_KEY` wins per Claude's documented precedence), `STARTUP_CMD`
6. Create `logs/` (0700); run the user's `init.sh`
7. **Start tmux *detached* at container boot**: `tmux new-session -d -s claude-main -c /config /opt/tmux-session.sh`. `tmux-session.sh` itself runs `tmux pipe-pane -o` on its pane into `exec /command/s6-log -b n3 s2000000 logs/` (guarded by `#{pane_pipe}` so it is never toggled off) so a session recreated by ttyd's `new-session -A` is logged too, and s6-log rotates `logs/current` at 2 MB keeping 3 old files
8. Run `ttyd ... bash -lc 'tmux new-session -A -s claude-main -c /config /opt/tmux-session.sh'` in a bounded restart loop: 5 exits within 120s → `exit 1` so the Supervisor watchdog restarts the add-on; SIGTERM/SIGINT are trapped and forwarded to ttyd. ttyd runs with `rendererType=dom` so text is selectable/copyable in WKWebView / the Companion app.

The detached tmux at step 7 is the **always-on inversion**: whatever the user puts in `startup_command` (e.g. `claude -c --channels plugin:telegram@claude-plugins-official`) starts at container boot regardless of whether anyone has opened the web terminal. ttyd attaches the browser to the already-running session.

Options are read through `opt()`: `bashio::config KEY` first (only when `SUPERVISOR_TOKEN` is set; under a local docker/podman run bashio would just log Supervisor errors; bashio fetches options from the Supervisor API and its default argument is `${2:-null}`, so an empty default is ignored and a missing key prints the literal `null`, which `opt()` maps to empty), `jq` on `/data/options.json` second, empty string last. The `startup_command` value is logged with `*TOKEN=`/`*KEY=`/`*SECRET=`/`*PASSWORD=` assignments redacted. The welcome banner is `welcome.sh`, copied to `/etc/profile.d/01-claude-terminal-welcome.sh` at build time (it used to be a heredoc written by `run.sh`).

### `tmux-session.sh`

Wrapper run inside the tmux session on first creation. Reads `STARTUP_CMD` from env (set by `run.sh` from the `startup_command` config option). If empty, just `exec bash -l`. If non-empty, runs it via `bash -lc "$STARTUP_CMD"` in a restart loop: backoff 5s doubling to 60s, reset to 5s after a run of >= 60s (which also clears the crash counter); 5 crash-like exits (run < 60s) within 600s → give up and drop to bash with a message; a `no-restart` file in `$CLAUDE_CONFIG_DIR` (fallback `/config/claude-config`) disables restarts; Ctrl+C during the countdown drops to bash. It traps INT with a handler rather than `''` so the child command still gets default SIGINT. `set -u` only, never `set -e`.

The command is passed via env, **not** interpolated into the tmux command line — this avoids quoting hell when the value contains quotes, spaces, or shell metacharacters.

### Add-on options

Four options in `config.yaml`, all optional.

| Option | Schema | Effect |
|---|---|---|
| `startup_command` | `str?` | Runs in tmux at boot inside the restart loop. `""` → plain bash; `claude`; `claude -c`; `claude -c --channels plugin:telegram@claude-plugins-official` → always-on Telegram bot. |
| `oauth_token` | `password?` | Exported as `CLAUDE_CODE_OAUTH_TOKEN` (from `claude setup-token`). |
| `api_key` | `password?` | Exported as `ANTHROPIC_API_KEY`. Outranks the OAuth token if both are set. |
| `claude_version` | `str?` | Pin the activated Claude Code version (must already be installed, else warning + newest); disables auto-update while set. |

`config.yaml` also sets `homeassistant_api: true` (Core API proxy at `http://supervisor/core/api`, bearer `SUPERVISOR_TOKEN`) for the helpers below. `hassio_api` is deliberately not requested; the only volume map is `config:rw`.

### Helper scripts (`bin/` → `/usr/local/bin/`)

| Script | Purpose |
|---|---|
| `claude-login [-q]` | Scrapes the last `https://claude.ai/oauth...` (or `console.anthropic.com/oauth...`) URL from every pane of the `claude-main` tmux session (skipping its own pane; `capture-pane -J` for soft wraps plus an awk pass that glues Ink's hard-wrapped URL lines back together), prints it, writes it to `$CLAUDE_CONFIG_DIR/login-url.txt` (0600) and QR-encodes it with `qrencode -t ANSIUTF8`. For WebViews where links aren't clickable. |
| `ha-check` | `POST /api/config/core/check_config` with a 5-minute budget (`timeout 310 curl --max-time 300`; distinct message on timeout; no `-f`, non-200 prints status + body); exit 0 only on `result == "valid"`; exit 2 if `SUPERVISOR_TOKEN` is unset (local docker run). |
| `ha-restart [-y]` | `ha-check`, refuse on invalid, confirm (needs a tty unless `-y`), `POST /api/services/homeassistant/restart`. |
| `ha-notify "title" "message"` | `POST /api/services/persistent_notification/create` with jq-built JSON. |

`ha-restart` and `ha-notify` use `timeout 30 curl`; plain `#!/bin/bash`, shellcheck-clean.

### Container build constraints

- Claude Code is installed via the **official native installer**: `curl -fsSL https://claude.ai/install.sh | bash -s ${CLAUDE_VERSION}`. This is the canonical install path per [Anthropic's setup docs](https://code.claude.com/docs/en/setup). The binary lands at `/root/.local/bin/claude`. System `ripgrep` plus `USE_BUILTIN_RIPGREP=0` in default `settings.json` keeps Claude off its bundled ripgrep.
- The add-on uses the **Debian (glibc) HA base image** (`ghcr.io/home-assistant/{arch}-base-debian:bookworm`) rather than the Alpine base. Reason: Claude Code's native installer starting at 2.1.64+ produces a binary that references `posix_getdents`, a musl symbol Alpine (still on 1.2.5 as of 2026-04) does not export, causing the binary to fail to relocate at runtime. Debian's glibc ships the symbol, so the native installer "just works." Anthropic's docs claim Alpine 3.19+ is supported; empirical testing shows that claim is broken for current releases — do not revert to the Alpine base without re-verifying.
- Claude Code version is pinned in the Dockerfile via `ENV CLAUDE_VERSION=...` — that pin is only the starting point for a fresh image; the install dir is persisted (see the symlink table above), so Claude's own auto-updater and manual `claude install X` both stick across restarts. Bump the pin deliberately for new installs anyway.
- Auto-update is enabled by default; image rebuilds are not the unit of update for an existing install. The `claude_version` option pins an installed version and exports `DISABLE_AUTOUPDATER=1` while set. Users can also add `"DISABLE_AUTOUPDATER": "1"` or `"autoUpdatesChannel": "stable"` to their own `settings.json`.
- **Bun** is installed via Bun's official installer. Required by Bun-based plugin runtimes such as the official Telegram channel.
- **ttyd** is downloaded from the upstream GitHub release and verified against that release's `SHA256SUMS`; the build fails on a mismatch.
- Multi-arch: `amd64` and `aarch64` only. armv7 was dropped because Bun ships no Linux armv7 build at all.

### Key environment variables

- `CLAUDE_CONFIG_DIR=/config/claude-config` — single source of truth for Claude Code state
- `HOME=/root`
- `STARTUP_CMD` — set by run.sh from the `startup_command` add-on option, read by `tmux-session.sh`
- `CLAUDE_CODE_OAUTH_TOKEN` / `ANTHROPIC_API_KEY` — set by run.sh from `oauth_token` / `api_key` when non-empty
- `DISABLE_AUTOUPDATER=1` — set by run.sh only while `claude_version` pins an installed version
- `SUPERVISOR_TOKEN` — injected by the Supervisor (`homeassistant_api: true`); used by the `ha-*` helpers
- `BUN_INSTALL=/usr/local` and `PATH` includes `/usr/local/bin` and `/root/.local/bin`

## File Conventions

- Shell scripts use `#!/usr/bin/with-contenv bashio` (when they need bashio helpers) or `#!/bin/bash` (for plain wrappers like `tmux-session.sh` and everything in `bin/`); they use `bashio::log.*` for logging when bashio is available. Keep them `shellcheck -s bash` clean.
- YAML: 2-space indent. Shell: 4-space indent.
- Auth files require `chmod 600`; persistent state directory `/config/claude-config` is `chmod 700`.

## Files in `claude-terminal/`

| File | Lands at | Role |
|---|---|---|
| `config.yaml`, `translations/en.yaml` | Supervisor | add-on manifest, options and their UI descriptions |
| `Dockerfile` | image | Debian base, apt packages, checksum-verified ttyd, Claude native installer, Bun |
| `run.sh` | `/run.sh` | boot script (see launch flow) |
| `tmux-session.sh` | `/opt/tmux-session.sh` | runs `STARTUP_CMD` in the restart loop |
| `welcome.sh` | `/etc/profile.d/01-claude-terminal-welcome.sh` | first-prompt banner |
| `bashrc.sh` | `/etc/profile.d/02-claude-terminal-bash.sh` | shell defaults; sources `bashrc.local` |
| `tmux.conf` | `/root/.tmux.conf` | tmux defaults; sources `tmux.conf.local` |
| `settings.default.json` | `/opt/claude-defaults/settings.json` | seeded to `/config/claude-config/settings.json` on first boot |
| `config-CLAUDE.md` | `/opt/claude-defaults/CLAUDE.md` | seeded to `/config/CLAUDE.md` on first boot |
| `bin/claude-login`, `bin/ha-check`, `bin/ha-restart`, `bin/ha-notify` | `/usr/local/bin/` | user-facing helpers |
| `README.md`, `DOCS.md`, `CHANGELOG.md` | add-on store | user-facing docs |

## Notes on other docs

- `DEVELOPMENT.md` — current dev workflow.
- `claude-terminal/CHANGELOG.md` — user-facing release notes; bump alongside `config.yaml:version`.
- `claude-terminal/DOCS.md` — what the user sees in the HA add-on store.
