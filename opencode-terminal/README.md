# OpenCode for Home Assistant

Run [OpenCode](https://opencode.ai) — an open-source AI coding agent — from your Home Assistant dashboard. The add-on exposes OpenCode's built-in web UI via HA ingress, so you click the sidebar panel and you're coding. No terminal required.

## What you get

- **Web UI in the HA dashboard.** Ingress-protected: only HA users can reach it.
- **Persistent state.** Sessions, auth, MCP credentials, and your `opencode.json` survive add-on restarts, HA updates, and HA backup/restore.
- **User-editable `opencode.json`.** Drop it at `/addon_configs/opencode_terminal/opencode.json` (visible over Samba or the File Editor add-on). Every provider, MCP server, and custom agent OpenCode supports is yours to configure.
- **Secrets through the HA UI.** Zhipu, Anthropic, OpenAI, Waha keys live in the add-on's Configuration tab as password fields — supervisor-encrypted, never plaintext in UI round-trips. Reference them from `opencode.json` with `{env:ZHIPU_API_KEY}`.
- **Batteries included.** Node + npm + Bun + git + gh + ripgrep + jq — so `npx`-based MCP servers (linkedin-mcp, nano-banana, waha-whatsapp, reddit-mcp, and friends) just work.

## Quick start

1. Install the add-on from your HA add-on store.
2. Click **Configuration**, paste any provider API keys you use (Zhipu, Anthropic, OpenAI, etc.), and set a **server_password**.
3. Click **Start**. Wait for the log to show `Starting OpenCode web on 0.0.0.0:7682`.
4. Open **`http://<hass-ip>:7682/`** in a new browser tab. Enter `opencode` as the user and your `server_password` when prompted.
5. OpenCode will prompt you to finish any provider setup. Once done, start a session.

> ⚠️ **The HA sidebar "OPEN WEB UI" button is currently broken** — it shows a blank page. OpenCode has no base-path support, so HA ingress can't proxy it correctly. Use the direct port URL above until upstream adds `--base-path`. See [DOCS.md](DOCS.md#ingress--subpath-asset-routing) for details.

## Customising `opencode.json`

The default seeded config is intentionally minimal. To add providers, MCP servers, or custom agents, edit the file at:

- **Via Samba** (add-on): `\\<hass>\addon_configs\opencode_terminal\opencode.json`
- **Via File Editor** (add-on): `/addon_configs/opencode_terminal/opencode.json`
- **Via SSH**: same path, or inside the container at `/config/opencode.json`

Restart the add-on (or the current session) for changes to take effect.

## Full docs

- [`DOCS.md`](DOCS.md) — full documentation: persistence model, customising, MCP setup, troubleshooting.
- [`CHANGELOG.md`](CHANGELOG.md) — release notes.

## License

MIT. OpenCode itself is MIT (see [opencode.ai](https://opencode.ai)).
