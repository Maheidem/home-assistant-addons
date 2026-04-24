# Changelog

All notable changes to this add-on. Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

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
