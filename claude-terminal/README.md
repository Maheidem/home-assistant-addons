# Claude Terminal for Home Assistant

A persistent web terminal with Anthropic's Claude Code CLI pre-installed. Open it from your HA dashboard, type `claude`, log in. Close the browser; your session keeps running. Reopen the add-on later — you're back where you left off.

![Claude Terminal Screenshot](https://github.com/heytcass/home-assistant-addons/raw/main/claude-terminal/screenshot.png)

## What you get

- **Web terminal** in the HA dashboard via ttyd, served through HA ingress
- **Claude Code CLI** pre-installed (pinned version, see `CHANGELOG.md`)
- **Persistent sessions** via tmux — close the browser, the terminal keeps running
- **Persistent everything** — auth, plugins, MCP servers, skills, agents, conversation history all live under `/config/claude-config/` and survive container restarts and add-on updates
- **One configuration knob** — `startup_command` lets you auto-run anything you want in the tmux session at boot (e.g. always-on Telegram bot)
- **Bun installed** so plugin runtimes that need it (Telegram channel, etc.) just work
- **Common dev tools** — git, github-cli, openssh-client, jq, yq-go, ripgrep, python3, nano, tree, nodejs, npm

## Installation

1. Add this repository to your HA add-on store
2. Install **Claude Terminal**
3. Start the add-on, click **OPEN WEB UI**
4. Type `claude` in the terminal, follow the OAuth browser prompts to log in

## The single configuration option

`startup_command` (string, optional). Whatever you put there runs in the tmux session at container boot.

```yaml
# Plain bash — type `claude` yourself when you want it (default)
startup_command: ""

# Auto-launch Claude on every boot
startup_command: "claude"

# Resume your most recent conversation on every boot
startup_command: "claude -c"

# Always-on Telegram bot — reachable 24/7, no browser required
startup_command: "claude -c --channels plugin:telegram@claude-plugins-official"
```

If the command exits, the tmux session falls through to a bash prompt so you can recover via the web terminal.

> **First-time:** leave `startup_command` empty so you can log in interactively, install plugins, configure them. Then set the command and restart the add-on.

## Architectures

`amd64` and `aarch64`. armv7 is not supported (Bun has no musl build for it).

## Documentation

See [DOCS.md](DOCS.md) for the full add-on docs, troubleshooting, and persistence details.

## Development

`nix develop` (or `direnv allow`) drops you into a shell with podman, hadolint, and a few aliases:

```bash
build-addon       # podman build of the amd64 image
run-addon         # run locally on :7681 with ./config mounted
lint-dockerfile   # hadolint
test-endpoint     # curl localhost:7681
```

See `DEVELOPMENT.md` for the full workflow.

## Credits

Originally forked from [heytcass/home-assistant-addons](https://github.com/heytcass/home-assistant-addons). The 2.0.0 rewrite collapses the previous credential-management and session-picker layers into a single `CLAUDE_CONFIG_DIR`-based persistence model.
