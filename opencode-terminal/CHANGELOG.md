# Changelog

All notable changes to this add-on. Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [1.0.3] - 2026-04-24

### Fixed

- Sidebar "OPEN WEB UI" showed a blank page. Root cause: OpenCode's web UI uses absolute asset paths (`<script src="/assets/app.js">`) and has no `--base-path` flag. HA ingress passes requests through at a subpath (`/api/hassio_ingress/<token>/`), so the HTML loads but every asset and XHR resolves to `https://<ha>:8123/assets/…` outside ingress and 404s. This is a known upstream limitation ([anomalyco/opencode](https://github.com/anomalyco/opencode)) — the binary has no `HASSIO`/`X-Ingress`/`URL_PREFIX` strings at all.

### Changed — **action required**

- Port `7682` is now exposed host-side by default. **Use `http://<hass-ip>:7682/` directly** until upstream adds base-path support. Clicking "OPEN WEB UI" through the HA sidebar will still show a blank page (we can't fix this without upstream changes).
- New `server_password` option (password field). When set, OpenCode enforces HTTP basic auth on every request. **Strongly recommended** because direct port access bypasses HA ingress's auth layer.
- `ingress_stream: true` added so streaming responses (chat token stream, tool output) pass through HA cleanly if/when ingress works.

### Known limitation

- HA sidebar panel still shows blank. Tracked as "needs upstream opencode base-path support" — see DOCS.md Troubleshooting section.

## [1.0.2] - 2026-04-24

### Fixed

- `/init: Permission denied` still occurred on 1.0.1. Root cause: commenting out `apparmor: true` in config.yaml does not disable AppArmor — HA's default is `apparmor: true`, and the supervisor auto-loads `apparmor.txt` from the add-on folder whenever one is present. The 1.0.0 profile was therefore still being applied.

### Changed

- `config.yaml` now sets `apparmor: false` explicitly.
- `apparmor.txt` removed from the add-on folder so no profile can be auto-loaded. Matches `claude-terminal`, which ships without an apparmor.txt at all. Will return in a future version with a properly-tested profile.

## [1.0.1] - 2026-04-24

### Fixed

- Container failed to start with `cannot open /init: Permission denied`. Root cause: the 1.0.0 AppArmor starter profile did not whitelist `/init` (the s6-overlay entrypoint the HA Debian base uses as PID 1). Shipped as complain-mode in the plan, but HA applied it in enforce mode in practice.

### Changed

- AppArmor disabled (`apparmor: true` → commented out in `config.yaml`). The profile file (`apparmor.txt`) is kept in-tree as a starting point for a future version but not currently loaded. This matches `claude-terminal` (which ships unconfined).

## [1.0.0] - 2026-04-24

Initial release. Sibling to `claude-terminal`, fully independent.

### Added

- OpenCode 1.14.22 (pinned via `OPENCODE_VERSION` in Dockerfile), installed via the official curl installer.
- HA ingress exposes `opencode web --hostname 0.0.0.0 --port 7682`.
- Persistent state under `/data/opencode/` — survives restarts, updates, and HA backup/restore.
- User-editable `opencode.json` at `/addon_configs/opencode_terminal/opencode.json` (host-visible via Samba and the File Editor add-on).
- Secrets via HA options schema (`password` type fields): Zhipu, Anthropic, OpenAI, Waha keys + an `extra_env` escape hatch.
- Pre-installed tooling for MCP and plugin work: Node + npm + Bun + git + gh + ripgrep + jq.
- Persistent symlinks for `~/.config/opencode`, `~/.local/share/opencode`, `~/.ssh`, `~/.gitconfig`, `~/.bash_history`, and `~/.config/{gh,npm,aws,gcloud,...}`.
- User hooks: `init.sh` (sourced at boot) and `bashrc.local` (sourced by interactive shells).
- Schema-version marker (`/data/opencode/.schema-version`) for future migrations.
- AppArmor starter profile (complain mode).
- Debian `bookworm` HA base image, amd64 + aarch64.

### Intentionally different from `claude-terminal`

- Uses `addon_config:rw` map instead of `config:rw` — tighter blast radius and inclusion in per-add-on backups.
- No ttyd / tmux layer — the product IS the HTTP server.
- Secrets through HA options schema rather than inlined in the config file.
