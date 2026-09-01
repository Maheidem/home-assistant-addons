# Development Guide

Local development and testing for the add-ons in this repo.

- **Claude Terminal** — sections below prefixed with `build-addon`, `run-addon`, etc.
- **OpenCode** — see [OpenCode local dev](#opencode-local-dev) at the bottom.

## Prerequisites

- Podman (or Docker)
- Git
- Optional: Nix or direnv (for the bundled dev shell)

## Quick start with Nix

```bash
nix develop          # or `direnv allow` once
build-addon          # podman build of the amd64 image
run-addon            # run locally on :7681 with ./config mounted
build-addon-arm64    # same build, aarch64 base image (tag local/claude-terminal:arm64)
run-addon-arm64      # run that aarch64 image on :7681
lint-dockerfile      # hadolint
test-endpoint        # curl localhost:7681
```

The aliases live in `flake.nix`. `build-addon` uses `ghcr.io/home-assistant/amd64-base-debian:bookworm` as the build base; the `-arm64` variants use `aarch64-base-debian:bookworm`.

> **Apple Silicon:** `amd64` cannot be built here under QEMU — the Bun installer crashes with `MemoryExhaustion` under emulation. Use `build-addon-arm64` / `run-addon-arm64` (native arm64) and leave amd64 builds to CI or an amd64 host.

## Quick start without Nix

```bash
# 1. Build
podman build \
  --build-arg BUILD_FROM=ghcr.io/home-assistant/amd64-base-debian:bookworm \
  -t local/claude-terminal:test \
  ./claude-terminal

# 2. Make a config dir for the add-on to write into
mkdir -p /tmp/claude-terminal-test
echo '{}' > /tmp/claude-terminal-test/options.json    # all defaults

# 3. Run
podman run --rm -it --name claude-terminal-test \
  -p 7681:7681 \
  -v /tmp/claude-terminal-test:/config \
  local/claude-terminal:test

# 4. Browse to http://localhost:7681

# 5. Clean up
podman stop claude-terminal-test  # if -d
rm -rf /tmp/claude-terminal-test
```

### Test the add-on options

`run.sh` reads options via bashio and falls back to `/data/options.json`; under a plain container run there is no `/data`, so mount one:

```bash
mkdir -p /tmp/claude-terminal-data
echo '{"startup_command": "claude", "oauth_token": "", "api_key": "", "claude_version": ""}' \
  > /tmp/claude-terminal-data/options.json
podman run --rm -it -p 7681:7681 \
  -v /tmp/claude-terminal-test:/config \
  -v /tmp/claude-terminal-data:/data \
  local/claude-terminal:test
# should auto-launch claude at boot (check `podman logs`), restart it with
# backoff when it exits, and log "oauth_token option set" etc. when those are set.
```

The `ha-*` helpers need `SUPERVISOR_TOKEN` and the `http://supervisor` proxy, which only exist inside HA; locally they exit 2 with a message saying so.

### Test persistence

```bash
# Stop and re-run with the same -v mount; conversation history,
# plugins, settings should still be there.
podman stop claude-terminal-test
podman run --rm -it -p 7681:7681 \
  -v /tmp/claude-terminal-test:/config \
  local/claude-terminal:test
```

## What to verify before tagging a release

- `claude --version` works inside the container
- `bun --version` works inside the container
- Browser can open and connect to ttyd on `:7681`
- After OAuth login, conversation persists across container stop/start
- A plugin install (e.g. `/plugin install telegram@claude-plugins-official`) survives a container restart
- `startup_command` runs at container boot **before** any browser is attached (verify by checking `podman logs`)
- When `startup_command` exits, it is restarted with backoff; after 5 crash-like exits in 10 min (or with `no-restart` present) the tmux session falls through to a bash prompt
- `/config/claude-config/logs/current` fills up with the tmux pane output and rolls over at 2 MB
- With `oauth_token` set in `options.json`, `podman exec claude-terminal-test env | grep CLAUDE_CODE_OAUTH_TOKEN` shows it and `podman logs` says "oauth_token option set (value not shown)"
- `claude-login -q` from `podman exec` prints the URL after `claude` was started without credentials
- Stopping the container (`podman stop`) returns within a couple of seconds (SIGTERM handled by `run.sh`)

## Iterating on shell scripts

Shell files and where they land in the image:

| Source | Destination |
|---|---|
| `run.sh` | `/run.sh` |
| `tmux-session.sh` | `/opt/tmux-session.sh` |
| `welcome.sh` | `/etc/profile.d/01-claude-terminal-welcome.sh` |
| `bashrc.sh` | `/etc/profile.d/02-claude-terminal-bash.sh` |
| `bin/*` | `/usr/local/bin/` |
| `settings.default.json`, `config-CLAUDE.md` | `/opt/claude-defaults/{settings.json,CLAUDE.md}` |

To iterate quickly without rebuilding the whole image:

```bash
podman cp ./claude-terminal/run.sh           claude-terminal-test:/run.sh
podman cp ./claude-terminal/tmux-session.sh  claude-terminal-test:/opt/tmux-session.sh
podman cp ./claude-terminal/bin/.            claude-terminal-test:/usr/local/bin/
podman exec claude-terminal-test chmod +x /run.sh /opt/tmux-session.sh
podman restart claude-terminal-test          # re-reads options.json
```

Lint before committing: `shellcheck -s bash claude-terminal/run.sh claude-terminal/tmux-session.sh claude-terminal/bashrc.sh claude-terminal/welcome.sh claude-terminal/bin/*` and `lint-dockerfile`.

For changes to apt packages or the Claude Code / Bun / ttyd versions, you need a full image rebuild.

## Debugging inside a running container

```bash
podman exec -it claude-terminal-test bash    # shell into the container
podman exec claude-terminal-test env | grep -E 'CLAUDE|BUN|STARTUP|ANTHROPIC'
podman exec claude-terminal-test tmux ls
podman exec claude-terminal-test tmux capture-pane -t claude-main -p | tail -30
podman exec claude-terminal-test tail -c 4000 /config/claude-config/logs/current
podman logs -f claude-terminal-test
```

## Common issues

- **Port already in use** — `lsof -ti:7681 | xargs kill -9`, or run on a different host port: `-p 7682:7681`
- **Volume permission errors** — make sure the host directory exists and is readable: `mkdir -p /tmp/claude-terminal-test && chmod 755 /tmp/claude-terminal-test`
- **OAuth flow seems stuck** — open the URL the terminal prints in any browser; the token is written back to `/config/claude-config/.credentials.json`
- **Telegram plugin returns HTTP 409** — a stale Bun process is holding the long-poll. Restart the container.

## Releasing

1. Bump `claude-terminal/config.yaml:version`
2. Add an entry to `claude-terminal/CHANGELOG.md`
3. Verify the smoke checklist above on local podman
4. Commit + tag + push. HA add-on store picks up the new version on its next refresh.

---

## OpenCode local dev

Same shape as Claude Terminal — different aliases, two volume mounts instead of one, and the primary surface is a web UI instead of a terminal.

### Quick start with Nix

```bash
nix develop
build-opencode              # podman build
run-opencode                # run on :7682, mounts ./opencode-terminal/.local-data and .local-config
lint-opencode-dockerfile
test-opencode-endpoint      # curl :7682
```

Then open `http://localhost:7682/` in a browser — OpenCode's web UI loads.

### Quick start without Nix

```bash
# 1. Build
podman build \
  --build-arg BUILD_FROM=ghcr.io/home-assistant/amd64-base-debian:bookworm \
  -t local/opencode-terminal:test \
  ./opencode-terminal

# 2. Prepare mounts (mirrors HA's /data + addon_config volumes)
mkdir -p /tmp/opencode-data /tmp/opencode-config
echo '{}' > /tmp/opencode-data/options.json          # bashio fallback

# 3. Run
podman run --rm -it --name opencode-terminal-test \
  -p 7682:7682 \
  -v /tmp/opencode-data:/data \
  -v /tmp/opencode-config:/config \
  local/opencode-terminal:test

# 4. Browse to http://localhost:7682/

# 5. Clean up
podman stop opencode-terminal-test
rm -rf /tmp/opencode-data /tmp/opencode-config
```

### Testing with secrets

Drop them into `options.json` — bashio falls back to it when the supervisor isn't reachable:

```bash
cat > /tmp/opencode-data/options.json <<'EOF'
{
  "log_level": "debug",
  "zhipu_api_key": "test-key-here",
  "extra_env": "CUSTOM_VAR=value"
}
EOF
```

### Testing persistence

```bash
podman stop opencode-terminal-test
podman run --rm -it -p 7682:7682 \
  -v /tmp/opencode-data:/data \
  -v /tmp/opencode-config:/config \
  local/opencode-terminal:test
```

Anything you wrote (sessions, auth, edits to `opencode.json`) should still be there.

### Iterating on shell scripts

Both `run.sh` and `opencode-boot.sh` are copied in by the Dockerfile. To iterate without a full rebuild:

```bash
podman cp ./opencode-terminal/run.sh          opencode-terminal-test:/run.sh
podman cp ./opencode-terminal/opencode-boot.sh opencode-terminal-test:/opt/opencode-boot.sh
podman exec opencode-terminal-test chmod +x /run.sh /opt/opencode-boot.sh
podman restart opencode-terminal-test
```

### Debugging inside a running container

```bash
podman exec -it opencode-terminal-test bash
podman exec opencode-terminal-test env | grep -E 'OPENCODE|ZHIPU|ANTHROPIC|OPENAI|WAHA'
podman exec opencode-terminal-test ls -la /data/opencode /config
podman logs -f opencode-terminal-test
```

### What to verify before tagging a release

- `opencode --version` works inside the container
- `bun --version`, `node --version`, `npx --version`, `gh --version` all work
- Web UI loads at `http://localhost:7682/` and does *not* 404 on assets
- Edits to `/config/opencode.json` on the host are picked up on restart
- Logging into a provider writes `/data/opencode/opencode-state/share/auth.json` (chmod 600)
- Add-on-private state (`/data/opencode/`) survives `podman stop` + fresh `podman run`
- Ingress smoke test on a real HA instance: asset paths resolve; streaming works

### Common issues

- **Port already in use** — `lsof -ti:7682 | xargs kill -9`, or run on a different host port: `-p 7683:7682`.
- **Volume permission errors** — `mkdir -p /tmp/opencode-data /tmp/opencode-config && chmod 755 /tmp/opencode-data /tmp/opencode-config`.
- **`opencode` binary not found** — installer failed during the build (rare, upstream blip). Re-run `build-opencode`.
- **Ingress shows assets 404** — known upstream issue (no `--base-path` flag yet). Workaround: expose the port directly and hit `http://<host>:7682/`.

### Releasing

1. Bump `opencode-terminal/config.yaml:version` and `opencode-terminal/Dockerfile:OPENCODE_VERSION` (if bumping OpenCode itself).
2. Add an entry to `opencode-terminal/CHANGELOG.md`.
3. Run the smoke checklist above on local podman.
4. Commit + tag + push.
