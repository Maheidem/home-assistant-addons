# Changelog

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