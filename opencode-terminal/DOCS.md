# OpenCode add-on documentation

## What this add-on does

Ships a container that runs [OpenCode](https://opencode.ai) in `web` mode. The HA dashboard's **OpenCode** sidebar panel reverse-proxies into the container via HA ingress. OpenCode's own web UI — session list, chat interface, tool invocations, file explorer, MCP browser — is what you see.

## Architecture

```
HA dashboard ─ingress─▶ 0.0.0.0:7682 ─opencode web─▶ your sessions + providers + MCPs
                          │
                          ├─ /config/opencode.json  (user-editable, addon_config)
                          └─ /data/opencode/...     (private state, addon-private volume)
                               ├─ opencode-state/share/  ← SQLite DB, auth.json, mcp-auth.json
                               ├─ opencode-state/config/ ← agents/, skills/, commands/
                               ├─ ssh/                   ← your SSH keys for git push
                               ├─ gitconfig              ← git identity
                               ├─ bash_history           ← shell history (rare use)
                               └─ dot-config/            ← gh, npm, aws, gcloud, etc.
```

### Persistence model

Two volumes, both included in HA's per-add-on backup stream:

| Path inside container | Host path | What lives here | Editable from HA? |
|---|---|---|---|
| `/data/opencode/` | (private, managed by supervisor) | SQLite DB, auth, SSH keys, git identity, snapshots — anything that should be private to the add-on | No (by design) |
| `/config/` | `/addon_configs/opencode_terminal/` | `opencode.json`, `bashrc.local`, `init.sh` — things you want to hand-edit | Yes — Samba, File Editor, SSH |

Unlike the sibling `claude-terminal` add-on, no state lives under `/config/claude-config/`. We intentionally follow the modern HA add-on pattern ([ref](https://developers.home-assistant.io/blog/2023/11/06/public-addon-config/)) so that:

- State *is* captured by HA per-add-on backups. A backup-wipe-restore cycle brings everything back.
- The add-on has **no** read/write access to HA's own `secrets.yaml` or `.storage/`. Tight blast radius.

## Configuration

### Secrets

The Configuration tab exposes:

| Field | What it's for |
|---|---|
| `zhipu_api_key` | Zhipu / GLM provider |
| `anthropic_api_key` | Claude via Anthropic API |
| `openai_api_key` | OpenAI / ChatGPT |
| `waha_api_key` + `waha_api_url` | Waha WhatsApp MCP server |
| `extra_env` | Anything else: one `KEY=VALUE` per line |

Each is exposed as an environment variable inside the container. Reference them from `opencode.json`:

```jsonc
{
  "provider": {
    "zhipu": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Zhipu AI (GLM)",
      "options": {
        "baseURL": "https://api.z.ai/api/coding/paas/v4/",
        "apiKey": "{env:ZHIPU_API_KEY}"
      }
    }
  }
}
```

### `log_level`

Passed to `opencode web --log-level …`. `trace|debug|info|notice|warning|error|fatal`. Default `info`.

### `extra_env`

Multi-line block. Example:

```
PATH_EXTRA=/some/bin
GH_HOST=github.example.com
OPENAI_BASE_URL=https://custom.example.com/v1
```

Lines starting with `#` are ignored. Malformed lines (no `=`) are skipped with a log warning.

## Editing `opencode.json`

The seeded default:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "autoupdate": false,
  "permission": { "edit": "ask", "bash": "ask", "webfetch": "allow" },
  "provider": {},
  "mcp": {}
}
```

To add a provider, MCP server, or custom agent, edit `/addon_configs/opencode_terminal/opencode.json` (host path) or `/config/opencode.json` (container path). Examples:

### Local LM Studio provider

```jsonc
{
  "provider": {
    "lmstudio": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "LM Studio",
      "options": { "baseURL": "http://192.168.31.222:1234/v1" },
      "models": {
        "qwen3.6-35b-a3b": {
          "name": "Qwen 3.6 35B MoE",
          "limit": { "context": 262144, "output": 8192 }
        }
      }
    }
  }
}
```

### Adding an MCP server

Local (spawns a subprocess via `npx`):

```jsonc
{
  "mcp": {
    "linkedin-complete": {
      "type": "local",
      "command": ["npx", "-y", "--package=@maheidem/linkedin-mcp", "linkedin-mcp-server"]
    }
  }
}
```

Remote (HTTP):

```jsonc
{
  "mcp": {
    "home-assistant-mcp": {
      "type": "remote",
      "url": "http://192.168.31.114:9583/private_<token>"
    }
  }
}
```

Restart the add-on after editing so OpenCode re-reads the file.

## Hooks

Three optional files under `/config/` (i.e. `/addon_configs/opencode_terminal/` on the host):

| File | Loaded by | When |
|---|---|---|
| `bashrc.local` | `/etc/profile.d/02-opencode-terminal-bash.sh` | Every interactive shell |
| `init.sh` | `run.sh` via `.` (source) | Once, at container boot, before opencode web starts |

`init.sh` runs as root with the environment already set up (HOME, PATH, OPENCODE_CONFIG, all the exported option env vars). Failures are logged but non-fatal — a broken hook can't block the container from starting.

## Tooling inside the container

The image ships the same baseline as claude-terminal:

- `opencode` (pinned via `OPENCODE_VERSION` in Dockerfile)
- `node`, `npm`, `npx` — for MCP servers that use `npx`
- `bun`, `bunx` — for OpenCode plugins and Bun-based MCPs
- `git`, `gh` — GitHub CLI auth persists in `/data/opencode/dot-config/gh/`
- `ripgrep` (`rg`), `jq`, `tree`, `nano`, `less`
- `openssh-client` — for git-over-SSH; keys persist in `/data/opencode/ssh/`
- `python3`

## Backups

HA's per-add-on backup captures `/data` and `/config` automatically. That's the full state — your sessions, your auth, your `opencode.json`. Restoring the backup into a freshly-installed add-on restores everything.

Do NOT expect `~/.claude` or other claude-terminal paths to survive in this add-on — they don't apply here. The two add-ons are fully independent.

## Troubleshooting

### The web UI is blank / 502 / timeout

Check the add-on **Log** tab for errors. Common causes:

- Provider API key rejected at startup → edit the key in the Configuration tab and restart.
- `opencode.json` has a syntax error → the startup log will flag a JSON parse error. Fix the file in `/addon_configs/opencode_terminal/opencode.json`, restart.
- Ingress routing weirdness (assets 404) → see next section.

### Ingress / subpath asset routing

**Known limitation, current as of v1.0.3.** OpenCode's web UI emits HTML with absolute asset paths (`<link href="/favicon..."`, `<script src="/assets/...">`), and the binary has no `--base-path` flag or `OPENCODE_BASE_PATH` env var. Behind HA ingress — which serves the add-on at `/api/hassio_ingress/<token>/` — the HTML loads fine but all the `/assets/...` URLs resolve to `https://<ha>:8123/assets/...` (outside ingress) and return 404. Result: blank page.

**What we ship:**

- Port 7682 is exposed on the Docker host by default, so **use the direct URL `http://<hass-ip>:7682/`** in a browser tab. This bypasses HA ingress entirely.
- The add-on supports an optional `server_password` option. When set, OpenCode enforces HTTP basic auth on every request (`opencode` is the username). **Strongly recommended** because direct port access does NOT go through HA's auth.

**If you need ingress to work** (want the HA sidebar button to show the UI), the only real fix is upstream — opencode needs a `--base-path` flag. Track / upvote / file: [github.com/anomalyco/opencode](https://github.com/anomalyco/opencode).

**If you want to block access from outside your LAN**: the HA Network tab lets you remove the host-side port mapping (set it blank). The add-on will still work, but only other containers on the same Docker network can reach it.

### MCP server won't auth

MCP OAuth tokens land in `/data/opencode/opencode-state/share/mcp-auth.json`. If it's missing or stale, the web UI's MCP tab should walk you through re-auth. Failing that, delete the file, restart the add-on, retry the OAuth flow.

### Provider credentials lost

`auth.json` lives at `/data/opencode/opencode-state/share/auth.json`. It's private to the add-on (root-owned, 0600). If it disappears after a HA restore, check whether the backup was a per-add-on backup (includes `/data`) or a partial backup that excluded add-on data.

### How do I see logs?

- **HA-level**: Settings → Add-ons → OpenCode → **Log** tab.
- **File-level**: `/data/opencode/opencode-state/share/log/` (growing set of daily log files from OpenCode itself).

### Upgrading OpenCode

Bump `OPENCODE_VERSION` in the Dockerfile and rebuild. The add-on philosophy matches `claude-terminal`: image rebuilds are the unit of update, autoupdate is seeded as `false`. You can set `"autoupdate": true` in your `opencode.json` to opt back in; the upgrade will write to the persistent install dir.

## Architecture deltas vs `claude-terminal`

| Aspect | claude-terminal | opencode-terminal |
|---|---|---|
| Primary UI | ttyd + tmux → Claude CLI | opencode web (HTTP server) |
| State volume | `/config/claude-config/` (via `config:rw`) | `/data/opencode/` (automatic) |
| User-editable hooks | `/config/claude-config/` (same dir as private state) | `/config/` (via `addon_config:rw`) |
| Backup coverage | ❌ Not in per-add-on backup | ✅ Included |
| HA-secret exposure | ❌ Read/write all of `/config` | ✅ Scoped to add-on |
| Schema-version marker | ❌ | ✅ At `/data/opencode/.schema-version` |
| AppArmor profile | ❌ | ✅ (complain-mode starter) |

None of this is a knock on claude-terminal — it was built before the modern HA pattern was widely adopted. A migration for claude-terminal is tracked separately.
