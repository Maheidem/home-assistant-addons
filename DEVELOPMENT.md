# Development Guide

Local development and testing for the Claude Terminal add-on.

## Prerequisites

- Podman (or Docker)
- Git
- Optional: Nix or direnv (for the bundled dev shell)

## Quick start with Nix

```bash
nix develop          # or `direnv allow` once
build-addon          # podman build of the amd64 image
run-addon            # run locally on :7681 with ./config mounted
lint-dockerfile      # hadolint
test-endpoint        # curl localhost:7681
```

The aliases live in `flake.nix`. They use `ghcr.io/home-assistant/amd64-base:3.21` as the build base.

## Quick start without Nix

```bash
# 1. Build
podman build \
  --build-arg BUILD_FROM=ghcr.io/home-assistant/amd64-base:3.21 \
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

### Test `startup_command`

```bash
echo '{"startup_command": "claude"}' > /tmp/claude-terminal-test/options.json
# restart the container; should auto-launch claude on browser attach (and at boot)
```

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
- When `startup_command` exits, the tmux session falls through to a bash prompt

## Iterating on shell scripts

`run.sh` and `tmux-session.sh` are the only two shell files. To iterate quickly without rebuilding the whole image:

```bash
podman cp ./claude-terminal/run.sh           claude-terminal-test:/run.sh
podman cp ./claude-terminal/tmux-session.sh  claude-terminal-test:/opt/tmux-session.sh
podman exec claude-terminal-test chmod +x /run.sh /opt/tmux-session.sh
podman restart claude-terminal-test          # bashio re-reads options.json
```

For changes to apk packages or the Claude Code / Bun versions, you need a full image rebuild.

## Debugging inside a running container

```bash
podman exec -it claude-terminal-test bash    # shell into the container
podman exec claude-terminal-test env | grep -E 'CLAUDE|BUN|STARTUP'
podman exec claude-terminal-test tmux ls
podman exec claude-terminal-test tmux capture-pane -t claude-main -p | tail -30
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
