# AI coding agents for Home Assistant

This repository ships two independent Home Assistant add-ons, each wrapping a different open-source AI coding agent:

| Add-on | What it wraps | Primary surface | Ingress port |
|---|---|---|---|
| **[Claude Terminal](claude-terminal/)** | Anthropic's Claude Code CLI | Web terminal (ttyd + tmux) | 7681 |
| **[OpenCode](opencode-terminal/)** | [OpenCode](https://opencode.ai) by Anomaly | `opencode web` (HTTP UI) | 7682 |

They are fully independent — separate containers, separate state, separate config. Install either or both.

Claude Terminal is an enhanced fork of [heytcass/home-assistant-addons](https://github.com/heytcass/home-assistant-addons). OpenCode is a fresh add-on built in 2026-04.

## Installation

1. **Settings → Add-ons → Add-on Store**
2. **⋮ menu → Repositories**
3. Add `https://github.com/Maheidem/home-assistant-addons`
4. Install either **Claude Terminal** or **OpenCode** (or both), start it, click **OPEN WEB UI**.

### First run

- **Claude Terminal**: type `claude` in the web terminal, follow OAuth prompts.
- **OpenCode**: open the Configuration tab, paste provider API keys, start the add-on, open the web UI.

## Add-on docs

- Claude Terminal: [README](claude-terminal/README.md) · [DOCS](claude-terminal/DOCS.md) · [CHANGELOG](claude-terminal/CHANGELOG.md)
- OpenCode: [README](opencode-terminal/README.md) · [DOCS](opencode-terminal/DOCS.md) · [CHANGELOG](opencode-terminal/CHANGELOG.md)

## Development

Repo includes a Nix flake (`flake.nix`) with podman, hadolint, and helper aliases for both add-ons:

```bash
nix develop                 # or `direnv allow` once

# Claude Terminal
build-addon                 # podman build
run-addon                   # :7681
lint-dockerfile
test-endpoint

# OpenCode
build-opencode              # podman build
run-opencode                # :7682
lint-opencode-dockerfile
test-opencode-endpoint
```

See `DEVELOPMENT.md` for the full workflow of both.

## License

MIT — see [LICENSE](LICENSE). Same as the original upstream.
