# Claude Terminal

A persistent web terminal for Home Assistant with Anthropic's Claude Code CLI pre-installed.

## What it does

Opens a terminal in your browser. Type `claude` to talk to Claude Code. Close the browser; the session keeps running. Reopen the add-on later and you're back exactly where you were.

Plugins, MCP servers, skills, agents, settings, and conversation history all persist under `/config/claude-config/`.

## Installation

1. Add this repository to your HA add-on store
2. Install **Claude Terminal**
3. Start the add-on
4. Click **OPEN WEB UI**
5. Type `claude` in the terminal — follow the OAuth browser prompts to log in
6. Use it. Close the browser whenever. Come back whenever.

## Configuration

The add-on has one option: `startup_command`.

| Value | What happens |
|---|---|
| `""` (default) | Bash prompt opens. Type `claude` yourself when you want it. |
| `claude` | Claude launches automatically every time the add-on starts. |
| `claude -c` | Claude resumes your most recent conversation on every add-on start. |
| `claude -c --channels plugin:telegram@claude-plugins-official` | Claude starts at boot with the Telegram channel active — your bot is reachable 24/7 even if you never open the web terminal. |
| Any shell command | Free-form. Use it for anything you want auto-running in the tmux session. |

When the configured command exits (crash, `/exit`, container stop), the tmux session falls through to a bash prompt. Reopen the web terminal to recover and re-launch.

### First-time setup for `startup_command`

The first time you install the add-on, leave `startup_command` empty. Open the web terminal, run `claude`, log in via OAuth, install any plugins you want (e.g. `/plugin install telegram@claude-plugins-official`), and configure them. Then go to the add-on configuration, set `startup_command` to whatever you want auto-run on boot, and restart the add-on.

If you set `startup_command` before logging in, the command will fail (no credentials), and the tmux session will drop to a bash prompt. Recover by opening the web terminal and running `claude` manually to log in.

## Persistence

Everything Claude Code writes is under `/config/claude-config/`:

- `.credentials.json` — your OAuth tokens
- `settings.json` — your settings
- `projects/` — conversation history (this is what `claude -c` reads)
- `plugins/` — installed plugins, including their dependencies
- `channels/` — channel state (Telegram bot token, allowlist, etc.)
- `agents/`, `skills/`, `hooks/`, `commands/`, etc.

Auxiliary user state lives in the same directory:

- `ssh/` — your SSH keys (so `git push` works across restarts)
- `gitconfig` — your git identity
- `dot-config/` — everything under `~/.config/` (GitHub CLI, npm, aws, gcloud, fly, anything)
- `bash_history` — your shell history
- `claude-installations/` — Claude Code binaries (versions from `claude install X` and auto-updater both land here)

This whole directory is the HA `/config` share, so everything survives container restarts, host reboots, and add-on updates. Do not delete it unless you want to start over.

## Customizing your environment

Three persistent hooks let you tune the shell, tmux, and container startup without editing anything inside the container (changes there are lost on restart):

### `/config/claude-config/bashrc.local`
Any shell aliases, env vars, functions, or PS1 tweaks. Sourced by every interactive bash session on top of the defaults.

```bash
# example contents
alias k=kubectl
export EDITOR=vim
export PROMPT_COMMAND='history -a'
```

### `/config/claude-config/tmux.conf.local`
tmux overrides. Sourced by the default `~/.tmux.conf` if the file exists.

```tmux
# example contents
set -g status on
bind r source-file ~/.tmux.conf \; display "Reloaded!"
```

### `/config/claude-config/init.sh`
Runs once at container boot (from `run.sh`). Good for custom symlinks, one-off exports, starting background helpers — anything shell-scriptable. Runs with `set -euo pipefail` inherited from `run.sh`; non-zero exit is logged but non-fatal.

```bash
#!/bin/bash
# example contents: symlink an extra config dir
ln -sfn /config/claude-config/my-stuff /root/.my-stuff
export MY_CUSTOM_VAR=hello
```

### Claude Code versions
Run `claude install X.Y.Z` inside the terminal to install a specific version — it writes to `/config/claude-config/claude-installations/versions/` and sticks across restarts. On every boot, the newest installed version is activated. To pin at a specific version, set `"DISABLE_AUTOUPDATER": "1"` inside the `env` object in `settings.json`.

## What ships in the container

- **Claude Code** — pinned version (see `CHANGELOG.md` for the current pin), installed via Anthropic's official native installer. Auto-updates are disabled inside the container; bump by updating the add-on.
- **Bun** — needed by some plugin runtimes (e.g. the official Telegram channel).
- **Node.js + npm** — for general-purpose dev work (not required by Claude itself with the native installer).
- **git, github-cli, openssh-client** — for working with repos from the terminal.
- **tmux** — keeps your session alive across browser closes.
- **ttyd** — the web terminal itself.
- **ripgrep, jq, yq-go, python3, nano, tree** — common CLI tools.

## Architectures supported

`amd64` and `aarch64`. Sufficient for all modern HA installs (NUCs, mini PCs, Raspberry Pi 4/5).

`armv7` (Pi 3 and older) is **not supported** because Bun does not ship a musl build for it, and Bun is needed by the Telegram channel plugin and other modern plugins.

## Access control

This add-on is restricted to **Home Assistant admin users only** (`panel_admin: true`). The add-on has read/write access to `/config` and read access to `/addons`. Treat anyone with admin access to your HA as having shell access to your config directory.

If you set `startup_command` to something that exposes Claude over a network (e.g. the Telegram channel), be sure to lock down the channel's allowlist. The Telegram plugin has a built-in pairing flow — see its README at <https://github.com/anthropics/claude-plugins-official/tree/main/external_plugins/telegram>.

## Troubleshooting

**The terminal is blank or stuck.** Refresh the browser; ttyd reattaches to the live tmux session. If still stuck, restart the add-on.

**Claude says "not logged in".** Run `claude /logout` then `claude` again to re-authenticate via OAuth.

**Telegram plugin errors with HTTP 409.** A stale Bun process is holding the Telegram polling connection. Restart the add-on (kills all processes, lets the plugin reclaim the lock).

**`startup_command` doesn't take effect.** The command is read at container boot. After changing it in the add-on configuration, you must **restart the add-on** for the new value to apply. Saving the config alone is not enough.

**Plugin installs disappear after restart.** They shouldn't. Verify `/config/claude-config/plugins/` exists and has files. If empty, the persistent volume is not mounting correctly — check the add-on's `map:` configuration or your HA storage setup.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) in this directory.
