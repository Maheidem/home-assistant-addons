# Claude Terminal for Home Assistant

A persistent web terminal with Anthropic's Claude Code CLI pre-installed. Open it from your HA dashboard, type `claude`, log in. Close the browser; the session keeps running. Reopen the add-on later and you are back where you left off.

![Claude Terminal Screenshot](https://github.com/heytcass/home-assistant-addons/raw/main/claude-terminal/screenshot.png)

## What you get

- **Web terminal** in the HA dashboard via ttyd, served through HA ingress
- **Claude Code CLI** pre-installed (pinned version, see `CHANGELOG.md`), auto-updating unless you pin it
- **Persistent sessions** via tmux. Close the browser, the terminal keeps running.
- **Persistent everything.** Auth, plugins, MCP servers, skills, agents, conversation history, SSH keys, git identity and `~/.config` all live under `/config/claude-config/` and survive restarts and add-on updates.
- **Login without copying anything.** The login URL is a clickable link in the terminal; `claude-login` prints it again as a QR code for phones and WebViews; or skip the browser entirely with the `oauth_token` / `api_key` options.
- **Always-on `startup_command`** with a restart loop. A Telegram bot comes back on its own after a crash, backs off if it keeps crashing, and gives up after five crashes in ten minutes so it does not spin.
- **Home Assistant helpers**: `ha-check` validates your config, `ha-restart` restarts Core only if the config is valid, `ha-notify` posts a notification. They use the Core API proxy (`homeassistant_api`), not the Supervisor API.
- **Version pin** with `claude_version` for setups where "it updated overnight" is not acceptable.
- **Bun installed** so plugin runtimes that need it (Telegram channel and others) work.
- **Common dev tools**: git, github-cli, openssh-client, jq, ripgrep, python3, nano, tree, nodejs, npm, qrencode

## Installation

1. Add this repository to your HA add-on store
2. Install **Claude Terminal**
3. Start the add-on, click **OPEN WEB UI**
4. Type `claude` in the terminal and click the login link it prints

## Configuration options

All optional. Defaults give you a plain terminal.

```yaml
# Auto-run something in the tmux session at boot (restarted if it exits)
startup_command: ""                                                    # plain bash (default)
startup_command: "claude"                                              # auto-launch Claude
startup_command: "claude -c"                                           # resume most recent conversation
startup_command: "claude -c --channels plugin:telegram@claude-plugins-official"   # always-on Telegram bot

# Log in without a browser (pick one)
oauth_token: ""     # from `claude setup-token` (Pro/Max/Team/Enterprise), exported as CLAUDE_CODE_OAUTH_TOKEN
api_key: ""         # Claude Console key, exported as ANTHROPIC_API_KEY (wins if both are set)

# Pin the Claude Code version activated at boot (must already be installed)
claude_version: ""  # e.g. "2.1.257"; empty = newest installed, auto-updates on
```

If `startup_command` exits it is restarted with a backoff (5s doubling to 60s; five crash-like exits in ten minutes drops to bash instead). Create `/config/claude-config/no-restart` to turn that off.

> **First-time:** leave `startup_command` empty so you can log in interactively, install plugins, configure them. Then set the command and restart the add-on.

## Architectures

`amd64` and `aarch64`. armv7 is not supported (Bun ships no Linux armv7 build).

## Documentation

See [DOCS.md](DOCS.md) for logging in, the always-on behaviour, helpers, persistence and backups, security, and troubleshooting.

## Development

`nix develop` (or `direnv allow`) drops you into a shell with podman, hadolint, and a few aliases:

```bash
build-addon       # podman build of the amd64 image
run-addon         # run locally on :7681 with ./config mounted
build-addon-arm64 # same, aarch64 base (what an Apple Silicon host can build natively)
run-addon-arm64
lint-dockerfile   # hadolint
test-endpoint     # curl localhost:7681
```

See `DEVELOPMENT.md` for the full workflow.

## Credits

Originally forked from [heytcass/home-assistant-addons](https://github.com/heytcass/home-assistant-addons). The 2.0.0 rewrite collapsed the previous credential-management and session-picker layers into a single `CLAUDE_CONFIG_DIR`-based persistence model.
