# Claude Terminal for Home Assistant

This repository ships a single Home Assistant add-on: **Claude Terminal**, a persistent web terminal with Anthropic's Claude Code CLI pre-installed. Open it from your HA dashboard, type `claude`, log in. Close the browser; your session keeps running. Reopen it later — you're back where you left off.

This is an enhanced fork of [heytcass/home-assistant-addons](https://github.com/heytcass/home-assistant-addons). The 2.0.0 rewrite collapses the previous credential-management and session-picker layers into a single `CLAUDE_CONFIG_DIR`-based persistence model and exposes one user-tunable `startup_command` option that supports always-on patterns like running Claude Code with the official Telegram channel.

## Installation

1. **Settings → Add-ons → Add-on Store**
2. **⋮ menu → Repositories**
3. Add `https://github.com/Maheidem/home-assistant-addons`
4. Install **Claude Terminal**, start it, click **OPEN WEB UI**
5. Type `claude` in the terminal, follow the OAuth prompts to log in

## Add-on docs

- [`claude-terminal/README.md`](claude-terminal/README.md) — feature overview
- [`claude-terminal/DOCS.md`](claude-terminal/DOCS.md) — full add-on documentation, configuration, troubleshooting
- [`claude-terminal/CHANGELOG.md`](claude-terminal/CHANGELOG.md) — release notes (2.0.0 is a breaking rewrite — see migration notes there)

## Development

Repo includes a Nix flake (`flake.nix`) with podman, hadolint, and helper aliases:

```bash
nix develop          # or `direnv allow` once
build-addon          # podman build of the amd64 image
run-addon            # run locally on :7681 with ./config mounted
lint-dockerfile      # hadolint
test-endpoint        # curl localhost:7681
```

See `DEVELOPMENT.md` for the full workflow.

## License

MIT — see [LICENSE](LICENSE). Same as the original upstream.
