# Changelog

## 2.1.0

Feature release. No breaking changes; upgrades from 2.0.x need no manual steps. See the upgrade notes at the end of this entry.

### Added
- **`oauth_token` option.** Long-lived token from `claude setup-token`, exported as `CLAUDE_CODE_OAUTH_TOKEN`. Browser-free login for always-on setups. Cannot establish Remote Control sessions (Claude Code limitation for setup-token auth).
- **`api_key` option.** Claude Console key, exported as `ANTHROPIC_API_KEY`. If both are set the API key wins (Claude Code's documented precedence) and a warning is logged.
- **`claude_version` option.** Pins the Claude Code version activated at boot. Only activates a version that is already installed; falls back to the newest with a warning otherwise. Sets `DISABLE_AUTOUPDATER=1` while pinned.
- **`claude-login [-q]`.** Pulls the last Claude OAuth login URL out of the tmux scrollback (soft and hard wraps rejoined), writes it to `/config/claude-config/login-url.txt` (0600) and renders a QR code. For the Companion app and other WebViews where links are not clickable.
- **`ha-check`, `ha-restart [-y]`, `ha-notify "title" "message"`.** Thin wrappers over the Supervisor's Core API proxy (`check_config`, with a 5-minute budget because it loads every integration; `homeassistant.restart` gated on a valid config plus confirmation; `persistent_notification.create`). Backed by the new `homeassistant_api: true`. `hassio_api` is deliberately not requested.
- **`startup_command` restart loop.** The command is restarted when it exits: 5s backoff doubling to 60s, reset after a run of 60s or more, give up after 5 crash-like exits (runs under 60s) in 10 minutes and drop to bash. Ctrl+C during the countdown cancels. `/config/claude-config/no-restart` disables restarts.
- **ttyd restart loop.** ttyd is restarted in place if it dies; 5 exits in 120s make the add-on exit 1 so the Supervisor watchdog restarts it. SIGTERM still stops the container promptly.
- **Session log.** tmux pane output is piped through `s6-log` into `/config/claude-config/logs/current`, rotated at 2 MB with three old files kept (about 8 MB tops). It can contain anything printed in the pane (login URLs, device codes); the directory is 0700 and lives inside the HA backup like the rest of `/config`.
- **Seeded `/config/CLAUDE.md`** (only if absent) with short guidance for Claude: this is a live HA install, back up before editing YAML, `ha-check` before `ha-restart`, never print secrets, which helpers exist.
- `flake.nix`: `build-addon-arm64` / `run-addon-arm64` aliases (aarch64 base image; what an Apple Silicon host can build natively).
- `qrencode` in the image, for `claude-login`.

### Changed
- **Non-fatal boot steps.** Seeding, install persistence, activation, pruning, symlinks, gh migration, session log and `init.sh` each log a warning on failure instead of aborting the boot. Only the persistent dir, env exports and tmux start can still abort it.
- **Symlink migration instead of `rm -rf`.** A non-empty real file or directory found where `~/.ssh`, `~/.config`, `~/.claude` and friends should be is moved to `/config/claude-config/migrated/<name>.<epoch>` instead of deleted.
- **Old Claude Code versions are pruned** at boot: the newest two plus the active one are kept.
- ttyd uses `rendererType=dom` so terminal text is real DOM text, selectable in WKWebView / the Companion app where the WebGL canvas gave nothing to select.
- Welcome banner moved from a runtime heredoc in `run.sh` to `welcome.sh`, copied into `/etc/profile.d/` at build time; text updated for the new options and helpers.
- Default `settings.json` moved from a Dockerfile `printf` to `settings.default.json`.
- Both secret options use the `password` schema type so the HA UI masks them; values only go into the environment, never onto a command line.
- armv7 note corrected: Bun ships no Linux armv7 build at all, not just no musl one.

### Removed
- The `addons:ro` volume map. Nothing used it.
- The Go `yq` binary. It had no consumer in the image. (The Nix dev shell still has `yq-go`; that is unrelated to the container.)

### Security
- **New installs get `permissions.deny` rules** in `settings.json`: `Read/Edit(//config/secrets.yaml)`, `Read/Edit(//config/.storage/**)`, `Read(//config/*.db)`, `Read(//config/*.db-*)`. These cover Claude's file tools, not shell commands you approve.
- **ttyd binary is checksum-verified** at build time against the release's `SHA256SUMS`; a mismatch fails the build.
- The container's reach is now `/config` plus the Core REST API only (the `addons` mount is gone; the Supervisor API was never requested).

### Upgrade notes
- All new options are optional and default to empty. An existing install behaves as before after the update, plus the restart loop on `startup_command` if you have one set. Create `/config/claude-config/no-restart` if you want the old run-once behaviour.
- **Existing `settings.json` files are not modified.** To merge the new deny rules into yours (with Claude not running):

  ```bash
  cd /config/claude-config && jq --slurpfile d /opt/claude-defaults/settings.json \
    '.permissions.deny = ((.permissions.deny // []) + $d[0].permissions.deny | unique)' \
    settings.json > settings.json.new && mv settings.json.new settings.json
  ```
- If you relied on `/addons` being visible inside the terminal, it no longer is.
- If you relied on `yq` inside the terminal, install it under `/config` (see "What does NOT persist" in DOCS.md) or use `python3 -c 'import yaml'` / `jq` for JSON.
- `/config/CLAUDE.md` is created if you do not have one. Delete it if you do not want it; it is not re-created while a file exists at that path.

## 2.0.4

Bug-fix release. No breaking changes (auto-migrates from 2.0.x).

### Fixed
- **`claude update` (and the built-in auto-updater) never activated the new version until the add-on was restarted.** The launcher at `/root/.local/bin/claude` was symlinked straight at `/config/claude-config/claude-installations/versions/X.Y.Z`. Claude Code >= 2.1.207 only self-manages a launcher whose symlink target is lexically under `~/.local/share/claude/versions/`, so this pointed-at-`/config` form read as a "custom launcher": updates installed but never activated, and the updater's own version cleanup was disabled. Fixed by symlinking through `/root/.local/share/claude/versions/` instead (same directory, different path).
- **An `exit` inside `init.sh` could kill the boot.** The hook was sourced directly into `run.sh`'s `set -euo pipefail` shell, so a non-zero exit anywhere in it (or an explicit `exit`) aborted the rest of boot. Now runs in a subshell — a broken hook can no longer take the add-on down with it. Tradeoff: exports inside `init.sh` no longer propagate to the rest of the container; use `bashrc.local` for env vars.
- **A second browser tab was refused.** `ttyd --max-clients 1` capped the web terminal at one connection, even though tmux already shares a single session across every connected client. Removed.
- **Browser "Leave site?" prompt on tab close.** Noise, since the tmux session survives a closed tab by design. Added `disableLeaveAlert=true`.

### Security
- **Port 7681 is no longer published by default.** Direct access to it is unauthenticated (ttyd has no login of its own) — ingress, which is proxied through HA's own auth, is the supported path in. Set a host port in the add-on's Network tab if you specifically want direct access.

### Changed
- Bumped pins: Claude Code 2.1.114 → 2.1.257, yq v4.44.5 → v4.53.6, Bun 1.3.12 → 1.4.0.
- Added a Supervisor watchdog (`http://[HOST]:[PORT:7681]/`) so the add-on restarts itself if ttyd stops answering.
- Removed the `--client-option 'copyOnSelect=true'` ttyd flag — ttyd 1.7.7 has no such option; copy-on-select is unconditional in ttyd regardless of flags, so the flag was inert.
- `ensure_symlink()` no longer tears down and recreates a symlink that's already correct.
- Corrected several stale doc references to `DISABLE_AUTOUPDATER` (auto-update has been enabled by default since 2.0.1) across `run.sh`, `Dockerfile`, `DOCS.md`, and the repo's `CLAUDE.md`.

### Notes
- Copy-in-the-HA-panel is unreliable: ttyd relies on the browser's own mouse-selection copy (`document.execCommand('copy')`) with no fallback Ctrl+C handler, and that behavior varies by browser and by whether the tab has focus. Investigation continues; no fix in this release.

## 2.0.3

Persist everything a user typically customizes. No breaking changes (auto-migrates from 2.0.x).

### Persisted automatically
- **`/root/.config/` wholesale** — any CLI that stores config under `~/.config/` (gh, npm, aws, gcloud, fly, etc.) now persists in `/config/claude-config/dot-config/` without extra setup.
- **Migration:** existing `/config/claude-config/config-gh/` is moved into `dot-config/gh/` on first 2.0.3 boot; your GitHub CLI auth carries over unchanged.

### New persistent hooks for customization
Drop files in `/config/claude-config/` and they're picked up on every boot:

- **`bashrc.local`** — shell aliases, env vars, functions, PS1 tweaks. Sourced by every interactive bash session on top of the defaults.
- **`tmux.conf.local`** — tmux overrides. Sourced by the default `~/.tmux.conf` if the file exists.
- **`init.sh`** — arbitrary shell run once at container boot (from `run.sh`). Great for custom symlinks, one-off exports, starting background helpers. Failures are logged but non-fatal.

See `DOCS.md` for examples.

### Welcome banner
Updated to summarize what's persistent and where to customize.

## 2.0.2

Bug-fix release. No breaking changes.

### Fixed
- **Telegram channel tokens (and any other plugin state under `~/.claude/`) now persist.** `CLAUDE_CONFIG_DIR=/config/claude-config` redirects Claude Code's own reads/writes, but plugins and channels (e.g. the bun-based Telegram bot) use the literal `$HOME/.claude/` path and don't honour the env var. `~/.claude/` was on the ephemeral container filesystem, so plugin state vanished on restart. Fixed by symlinking `/root/.claude` → `/config/claude-config/` so both paths resolve to the same persistent volume.

### Upgrade notes
- Anything you had previously configured under `~/.claude/` that wasn't accessed via `CLAUDE_CONFIG_DIR` (Telegram bot token, any plugin state) was lost when you last restarted. Re-configure once on 2.0.2; it will stick from then on.

## 2.0.1

Bug-fix release. No breaking changes.

### Fixed
- **Claude Code updates now persist.** `claude install X` and the built-in auto-updater both wrote to `/root/.local/share/claude/versions/`, which was inside the container (not on the persistent volume). Updates vanished on add-on restart. Fixed by symlinking the install dir into `/config/claude-config/claude-installations/` and re-pointing `/root/.local/bin/claude` at the newest installed version on every boot.
- **Auto-updater re-enabled by default.** 2.0.0 shipped with `DISABLE_AUTOUPDATER=1` on the premise that "the image is the unit of update." With the persistence fix above, Claude can self-update safely, so the default is removed. Users who want to pin can add `"DISABLE_AUTOUPDATER": "1"` to `env` in `/config/claude-config/settings.json` themselves.
- **Bumped pinned Claude Code version** from 2.1.89 to **2.1.114**.

### Upgrade notes
- If you're on 2.0.0 and manually ran `claude install X`, that version was lost. Either let the auto-updater pull the latest, or re-run `claude install X`. With 2.0.1 it will stick.
- If you explicitly want 2.0.0's "no auto-update" behavior back, edit `/config/claude-config/settings.json` and add `"DISABLE_AUTOUPDATER": "1"` inside the `env` object. Existing 2.0.0 `settings.json` files already have this entry and will keep working unchanged (the defaults only seed when the file doesn't exist).

## 2.0.0

Major rewrite focused on simplicity and a single, predictable persistence model. **Breaking changes** — see migration notes below.

### Breaking changes
- **Removed config options:** `auto_launch_claude` and `persistent_sessions`. Replaced by a single `startup_command` (string) option that lets you control exactly what runs in the tmux session at boot.
- **Dropped armv7 architecture.** Bun (required by the official Telegram channel plugin and other modern Bun-based runtimes) does not ship a musl build for armv7. amd64 and aarch64 are still supported.
- **Removed `claude-auth` and `claude-logout` helper scripts.** Use `claude /logout` and re-run `claude` instead — Claude Code's built-in OAuth flow is reliable on Alpine now and these wrappers were paving over a problem that no longer exists.

### What changed under the hood
- **Switched to Anthropic's official native installer** for Claude Code, landing at `/root/.local/bin/claude`. The image also switched to HA's **Debian (glibc) base** (`ghcr.io/home-assistant/{arch}-base-debian:bookworm`) — Alpine's musl (1.2.5) does not export `posix_getdents`, a symbol the native installer requires starting at 2.1.64+. Debian ships glibc, so the native installer works out of the box. System `ripgrep` plus `USE_BUILTIN_RIPGREP=0` remains the ripgrep story.
- **`CLAUDE_CONFIG_DIR=/config/claude-config`** replaces the old symlinks for Claude Code's own state (`.claude`, `.claude.json`). Auxiliary user state (`.ssh`, `.gitconfig`, `.config/gh`, `.bash_history`) is still symlinked into the same persistent volume, so SSH keys for `git push`, your git identity, GitHub CLI auth, and shell history all carry over across restarts and add-on updates exactly as before.
- **Auto-update disabled** inside the container (`DISABLE_AUTOUPDATER=1`). The image is the unit of update; bump the add-on to bump Claude Code.
- **`run.sh` shrank from ~180 lines to ~50.** The session picker, auto-session manager, and credential monitor scripts were deleted — none were needed once the persistence model was simplified.
- **tmux now starts detached at container boot**, not lazily on first browser attach. This is what makes `startup_command` a true always-on option: a value like `claude -c --channels plugin:telegram@claude-plugins-official` keeps the bot running 24/7 even if you never open the web terminal.
- **Bun added to the image** so plugin runtimes that need it (Telegram channel, etc.) just work.

### New features
- **`startup_command` add-on option.** Set it to any shell command and it runs in the tmux session at boot. Empty (default) gives you a plain bash prompt. When the command exits, the tmux session falls through to bash so you can reconnect via the web terminal and recover.
- **First-prompt welcome banner** with quick orientation, written into `/etc/profile.d/`.

### Migration from 1.x
- After updating, your existing `/config/claude-config/` directory works as-is. Auth, plugins, conversation history all carry over.
- The two old options (`auto_launch_claude`, `persistent_sessions`) are silently ignored. To restore "Claude launches automatically", set `startup_command: claude` in the add-on configuration. To resume your most recent conversation on every boot, use `claude -c`.
- If you were on an armv7 device, you can no longer install this add-on. Stay on 1.x or move to amd64/aarch64 hardware.

## 1.1.4

### 🧹 Maintenance
- **Cleaned up repository**: Removed erroneously committed test files (thanks @lox!)
- **Improved codebase hygiene**: Cleared unnecessary temporary and test configuration files

## 1.1.3

### 🐛 Bug Fixes
- **Fixed session picker input capture**: Resolved issue with ttyd intercepting stdin, preventing proper user input
- **Improved terminal interaction**: Session picker now correctly captures user choices in web terminal environment

## 1.1.2

### 🐛 Bug Fixes
- **Fixed session picker input handling**: Improved compatibility with ttyd web terminal environment
- **Enhanced input processing**: Better handling of user input with whitespace trimming
- **Improved error messages**: Added debugging output showing actual invalid input values
- **Better terminal compatibility**: Replaced `echo -n` with `printf` for web terminals

## 1.1.1

### 🐛 Bug Fixes  
- **Fixed session picker not found**: Moved scripts from `/config/scripts/` to `/opt/scripts/` to avoid volume mapping conflicts
- **Fixed authentication persistence**: Improved credential directory setup with proper symlink recreation
- **Enhanced credential management**: Added proper file permissions (600) and logging for debugging
- **Resolved volume mapping issues**: Scripts now persist correctly without being overwritten

## 1.1.0

### ✨ New Features
- **Interactive Session Picker**: New menu-driven interface for choosing Claude session types
  - 🆕 New interactive session (default)
  - ⏩ Continue most recent conversation (-c)
  - 📋 Resume from conversation list (-r) 
  - ⚙️ Custom Claude command with manual flags
  - 🐚 Drop to bash shell
  - ❌ Exit option
- **Configurable auto-launch**: New `auto_launch_claude` setting (default: true for backward compatibility)
- **Added nano text editor**: Enables `/memory` functionality and general text editing

### 🛠️ Architecture Changes
- **Simplified credential management**: Removed complex modular credential system
- **Streamlined startup process**: Eliminated problematic background services
- **Cleaner configuration**: Reduced complexity while maintaining functionality
- **Improved reliability**: Removed sources of startup failures from missing script dependencies

### 🔧 Improvements
- **Better startup logging**: More informative messages about configuration and setup
- **Enhanced backward compatibility**: Existing users see no change in behavior by default
- **Improved error handling**: Better fallback behavior when optional components are missing

## 1.0.2

### 🔒 Security Fixes
- **CRITICAL**: Fixed dangerous filesystem operations that could delete system files
- Limited credential searches to safe directories only (`/root`, `/home`, `/tmp`, `/config`)
- Replaced unsafe `find /` commands with targeted directory searches
- Added proper exclusions and safety checks in cleanup scripts

### 🐛 Bug Fixes
- **Fixed architecture mismatch**: Added missing `armv7` support to match build configuration
- **Fixed NPM package installation**: Pinned Claude Code package version for reliable builds
- **Fixed permission conflicts**: Standardized credential file permissions (600) across all scripts
- **Fixed race conditions**: Added proper startup delays for credential management service
- **Fixed script fallbacks**: Implemented embedded scripts when modules aren't found

### 🛠️ Improvements
- Added comprehensive error handling for all critical operations
- Improved build reliability with better package management
- Enhanced credential management with consistent permission handling
- Added proper validation for script copying and execution
- Improved startup logging for better debugging

### 🧪 Development
- Updated development environment to use Podman instead of Docker
- Added proper build arguments for local testing
- Created comprehensive testing framework with Nix development shell
- Added container policy configuration for rootless operation

## 1.0.0

- First stable release of Claude Terminal add-on:
  - Web-based terminal interface using ttyd
  - Pre-installed Claude Code CLI
  - User-friendly interface with clean welcome message
  - Simple claude-logout command for authentication
  - Direct access to Home Assistant configuration
  - OAuth authentication with Anthropic account
  - Auto-launches Claude in interactive mode