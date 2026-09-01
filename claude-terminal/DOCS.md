# Claude Terminal

A persistent web terminal for Home Assistant with Anthropic's Claude Code CLI pre-installed.

## What it does

Opens a terminal in your browser. Type `claude` to talk to Claude Code. Close the browser; the session keeps running. Reopen the add-on later and you are back where you were.

Plugins, MCP servers, skills, agents, settings, and conversation history all persist under `/config/claude-config/`.

## Installation

1. Add this repository to your HA add-on store
2. Install **Claude Terminal**
3. Start the add-on
4. Click **OPEN WEB UI**
5. Type `claude` in the terminal and log in (see [Logging in](#logging-in))
6. Use it. Close the browser whenever. Come back whenever.

## Logging in

Claude Code needs a Pro, Max, Team, Enterprise, or Console account. There are three ways to log in from this add-on. Try them in this order.

### 1. Click the URL Claude prints

Run `claude`. It prints a login URL. In the web terminal that URL is a clickable link: click it and it opens in a new browser tab. This also works when the URL wraps over several lines; the whole thing is one link. Sign in there.

If the browser shows a code instead of sending you back, paste it into the terminal. Claude Code's docs describe this: "If your browser shows a login code instead of redirecting back after you sign in, paste it into the terminal at the `Paste code here if prompted` prompt. This happens when the browser can't reach Claude Code's local callback server, which is common in WSL2, SSH sessions, and containers." That is the normal case here, since Claude runs inside a container.

### 2. `claude-login`

For the HA Companion app or any WebView where the link is not clickable and copying does not work. Leave Claude waiting at the login prompt, open a second tmux window with `Ctrl+b c`, and run:

```bash
claude-login
```

It finds the last login URL in the tmux scrollback (wrapped lines are joined back together), prints it, writes it to `/config/claude-config/login-url.txt` (mode 0600, so open it from the File editor add-on or Samba if that is easier), and renders a QR code you can scan with a phone. Sign in on the other device, then paste the code back into Claude's pane if it asks. `Ctrl+b 0` takes you back to Claude's window. `claude-login -q` skips the QR code.

The URL carries a one-time OAuth state, so treat the file like a credential. Delete it after use if you want.

### 3. The `oauth_token` or `api_key` option

No browser is involved on the HA side. Best for always-on setups where nobody is around to click.

**`oauth_token`**: on any machine where you can complete a browser login (your laptop is fine), install Claude Code and run:

```bash
claude setup-token
```

It opens the same browser flow as `/login` and prints a long-lived token. Per Claude Code's docs, "generate a one-year OAuth token with `claude setup-token`" and "It does not save the token anywhere; copy it and set it as the `CLAUDE_CODE_OAUTH_TOKEN` environment variable". Paste it into the `oauth_token` option and restart the add-on. The add-on exports it as `CLAUDE_CODE_OAUTH_TOKEN`.

Two caveats from the same docs page:

- "This token authenticates with your Claude subscription and requires a Pro, Max, Team, or Enterprise plan."
- "It can only make model requests, so it can't establish Remote Control sessions or fetch claude.ai connectors. MCP servers you configure locally still work." So a session running on a setup-token cannot be driven through Remote Control. If you need that, log in interactively instead (paths 1 or 2).

**`api_key`**: a Claude Console API key, pay-as-you-go billing. Exported as `ANTHROPIC_API_KEY`. If both options are set, the API key wins. That is Claude Code's documented precedence: `ANTHROPIC_API_KEY` is checked before `CLAUDE_CODE_OAUTH_TOKEN`. The add-on logs a warning when both are set.

**Where these values end up.** The `password` schema type only masks them in the HA UI. Home Assistant stores add-on option values in plaintext in the add-on's options file, and they are included when the add-on is part of a backup. Anyone who can read your backups or the Supervisor's data can read the token. Inside the container the values are placed in the environment only, never on a command line.

## Configuration

All four options are optional. Changes apply on the next add-on restart.

| Option | Type | Default | What it does |
|---|---|---|---|
| `startup_command` | string | `""` | Command to run inside the tmux session at container boot, restarted with backoff if it exits. Empty gives you a plain bash prompt. See [Always-on](#always-on-startup_command). |
| `oauth_token` | password | `""` | Long-lived token from `claude setup-token`. Exported as `CLAUDE_CODE_OAUTH_TOKEN`. |
| `api_key` | password | `""` | Claude Console API key. Exported as `ANTHROPIC_API_KEY`. Takes precedence over `oauth_token` if both are set. |
| `claude_version` | string | `""` | Pin the Claude Code version that is activated at boot, e.g. `2.1.257`. See below. |

### `startup_command` values

| Value | What happens |
|---|---|
| `""` (default) | Bash prompt. Type `claude` yourself. |
| `claude` | Claude launches every time the add-on starts. |
| `claude -c` | Claude resumes the most recent conversation on every start. |
| `claude -c --channels plugin:telegram@claude-plugins-official` | Claude starts at boot with the Telegram channel active. The bot is reachable whether or not the web terminal is open. |
| Any shell command | Free-form. Runs through `bash -lc`. |

**First-time setup:** leave `startup_command` empty. Open the web terminal, run `claude`, log in, install any plugins you want (for example `/plugin install telegram@claude-plugins-official`), and configure them. Then set `startup_command` and restart the add-on. If you set it before logging in and without `oauth_token` or `api_key`, Claude sits at the login prompt; open the web terminal and use path 1 or 2 above.

### `claude_version` pin semantics

- The pin only **activates** a version that is already installed under `/config/claude-config/claude-installations/versions/`. It does not download anything.
- If the pinned version is not installed, the add-on logs a warning and activates the newest installed version instead. To fix that, run `claude install 2.1.257` (your version) once from the terminal, then restart the add-on.
- While the pin is in effect, the add-on sets `DISABLE_AUTOUPDATER=1` so a background update cannot replace the version you chose. `claude update` and `claude install` still work if you run them by hand.
- Empty (default): the newest installed version is activated on every boot and Claude Code's auto-updater stays on.
- Old versions are pruned at boot: the newest two plus the active one are kept, everything else under `versions/` is deleted.

## Always-on `startup_command`

The command runs inside a detached tmux session that is created at container boot, before any browser is attached. The web terminal attaches to that session; closing the browser does not stop it.

### Restart loop

When the command exits (crash, `/exit`, an update that restarts the process) it is started again:

- The first restart waits 5 seconds. Each further quick exit doubles the wait, up to 60 seconds.
- A run that lasted 60 seconds or more counts as healthy and resets the wait to 5 seconds.
- Five crash-like exits (runs shorter than 60 seconds) within ten minutes: the loop gives up, prints a message in the session, and drops to a bash prompt. Fix the cause, then run `exec /opt/tmux-session.sh` in that window (or restart the add-on) to resume. Healthy runs do not count towards this and clear it, so a bot that dies every few minutes keeps being restarted.
- Ctrl+C during the countdown cancels the restart and gives you a shell. Same recovery: `exec /opt/tmux-session.sh`.
- To turn restarts off entirely, create the file `/config/claude-config/no-restart`. The command then runs once and the session falls through to bash when it exits. Delete the file to turn restarts back on. Note that once the loop has dropped to bash there is no "next exit" to notice the change: run `exec /opt/tmux-session.sh` in that window, or restart the add-on.

### Session log

Everything the tmux session prints is written to `/config/claude-config/logs/current`, raw, including terminal escape sequences. Read it with `less -R`. This is where you look when a `startup_command` crashed while nobody was watching.

The log is rotated while the add-on runs (by `s6-log`, which the HA base image ships): `current` is rolled over at 2 MB into a timestamped `@...s` file in the same directory and the three most recent of those are kept, so the directory stays under about 8 MB no matter how long the bot runs or how busy the TUI is.

The log contains whatever appeared in the pane: login URLs, `gh auth` device codes, the contents of any file you `cat`. Treat it like the rest of `/config/claude-config` (the directory is mode 0700), and remember that `/config` is included in HA backups. Delete the directory contents whenever you like; a new `current` is started on the next add-on restart.

### ttyd restart loop and watchdog

The web terminal process (ttyd) is separate from the tmux session. If ttyd dies, the add-on restarts it in place after 2 seconds; the tmux session, and whatever `startup_command` is running in it, is not affected. If ttyd exits five times within two minutes the add-on itself exits, and the Supervisor watchdog (configured to poll port 7681) restarts the whole add-on.

### Running a bot unattended

If `startup_command` exposes Claude over a network (the Telegram channel is the common case), you are running a process that can read and edit your Home Assistant configuration on behalf of whoever the channel lets in. Two things matter:

- Lock down the channel's allowlist. The Telegram plugin has a pairing flow and an allowlist; use it, and do not leave the bot open to any user who finds it. Plugin README: <https://github.com/anthropics/claude-plugins-official/tree/main/external_plugins/telegram>.
- Treat bot tokens like SSH keys. They live under `/config/claude-config/channels/` and end up in your backups (see [Backups](#backups)). Rotate them if a backup leaks.

For a bot you rely on, consider moving Claude Code to the stable release channel so background updates do not hand you a regression at 3 a.m. Claude Code's setup docs describe the setting: "Control which release channel Claude Code follows for auto-updates and `claude update` with the `autoUpdatesChannel` setting", where `"latest"` is "the default: receive new features as soon as they're released" and `"stable"` means "use a version that is typically about one week old, skipping releases with major regressions". Add it to `/config/claude-config/settings.json`:

```json
{
  "autoUpdatesChannel": "stable"
}
```

Or pin outright with the `claude_version` option, which turns background updates off completely.

## Home Assistant helpers

The add-on requests `homeassistant_api: true`. That grants access to the Supervisor's Core API proxy at `http://supervisor/core/api`, authenticated with the `SUPERVISOR_TOKEN` the Supervisor injects. It is the narrowest grant that covers these helpers: it exposes Home Assistant Core's REST API only. The add-on does **not** request `hassio_api` (add-on management, host reboot, backups).

Three wrappers ship in the image:

| Command | What it calls | Behaviour |
|---|---|---|
| `ha-check` | `POST /api/config/core/check_config` | Prints the JSON result. Exit 0 only when `result` is `valid`, so it can gate a script. Waits up to 5 minutes (`check_config` loads every integration and takes a minute or more on large installs); says so distinctly if it times out. On a non-200 answer it prints the status and the body. |
| `ha-restart [-y]` | `homeassistant.restart` service | Runs `ha-check` first and refuses on an invalid config. Asks `Restart Home Assistant Core? [y/N]` unless `-y` is given. |
| `ha-notify "title" "message"` | `persistent_notification.create` service | Puts a notification in the HA frontend. Useful from a hook or script to say Claude finished something. |

Under a plain `docker run` (no Supervisor) `SUPERVISOR_TOKEN` is unset and all three exit 2 with a message saying so.

### Seeded `/config/CLAUDE.md`

On first boot the add-on writes `/config/CLAUDE.md` if the file does not exist. Claude Code reads it as project instructions whenever it runs in `/config`. It tells Claude what the directory is (a live HA install), what to leave alone (`.storage/`, `secrets.yaml`, the recorder database, `claude-config/`), to back up before editing YAML, to run `ha-check` before `ha-restart`, and which helpers exist. Edit it to taste or delete it; it is never overwritten while present.

## Persistence

Everything Claude Code writes is under `/config/claude-config/`:

- `.credentials.json`: your OAuth tokens
- `settings.json`: your settings. Seeded once with system ripgrep and the deny rules listed under [Security](#security). Edit freely; it is never overwritten.
- `projects/`: conversation history (what `claude -c` resumes)
- `plugins/`: installed plugins, including their dependencies
- `channels/`: channel state (Telegram bot token, allowlist, and so on)
- `agents/`, `skills/`, `hooks/`, `commands/`, and the rest

Auxiliary user state lives in the same directory:

- `ssh/`: your SSH keys, so `git push` works across restarts
- `gitconfig`: your git identity
- `dot-config/`: everything under `~/.config/` (GitHub CLI, npm, aws, gcloud, fly, anything)
- `bash_history`: shell history
- `claude-installations/`: Claude Code binaries. Versions from `claude install X` and from the auto-updater both land here. Pruned at boot to the newest two plus the active one.
- `logs/`: the session log described above (`current` plus rotated files)
- `login-url.txt`: written by `claude-login`
- `migrated/`: only appears if a real file or directory was found where one of the add-on's symlinks belongs. It is moved here with a timestamp suffix instead of being deleted.

This directory is on the HA `/config` share, so it survives container restarts, host reboots, and add-on updates. Do not delete it unless you want to start over.

### What does NOT persist

Anything outside `/config` is part of the container image and is reset on every restart or update:

- Packages installed with `apt-get install`
- Global installs from `npm install -g`, `bun install -g`, or anything else that writes under `/usr`, `/root/.local` (other than the Claude install dir), or `/root/.cache`
- Python packages. The image has `python3` but no `pip`; if you add one with apt it disappears too.
- Edits to files inside the container, including `/etc/profile.d/*` and `/root/.tmux.conf` (use the hooks below instead)

The fix is to point the tool at a prefix under `/config` and put that prefix on `PATH` from `bashrc.local`, which is sourced by every interactive shell:

```bash
# /config/claude-config/bashrc.local

# npm globals
export NPM_CONFIG_PREFIX=/config/claude-config/npm-global
export PATH="${NPM_CONFIG_PREFIX}/bin:${PATH}"

# bun globals
export BUN_INSTALL_GLOBAL_DIR=/config/claude-config/bun-global
export BUN_INSTALL_BIN=/config/claude-config/bun-global/bin
export PATH="${BUN_INSTALL_BIN}:${PATH}"
```

After that, `npm install -g foo` and `bun install -g foo` land under `/config/claude-config/` and are still there after a restart. For Python, keep a virtualenv or a `uv` install under `/config` and add its `bin/` to `PATH` the same way.

For apt packages there is no persistent prefix. If you must have one, install it from `init.sh` at every boot (`apt-get update && apt-get install -y foo`). That costs boot time and needs network access each time, so prefer a tool that can live under `/config`.

### Backups

`/config/claude-config/` is inside the Home Assistant configuration folder, so it is part of every backup that includes Home Assistant settings. Two consequences:

**Size.** `claude-installations/` holds Claude Code binaries, roughly 200 MB each. Pruning keeps it to two or three versions, but check before you are surprised by a large backup:

```bash
du -sh /config/claude-config/claude-installations /config/claude-config
```

Home Assistant's backup selection works at the level of whole folders and add-ons ("A partial backup consists of any number of the above default directories and installed apps"), not subfolders, so you cannot exclude just `claude-installations/` from the configuration folder. If the size is a problem, delete unneeded entries under `claude-installations/versions/` before the backup runs; the add-on re-seeds the image's pinned version on the next boot if the directory ends up empty.

**Credentials.** The backup contains everything needed to act as you: `.credentials.json`, `ssh/`, the channel tokens under `channels/`, and the `oauth_token` / `api_key` option values in the add-on's own data. Home Assistant's docs say backups are encrypted: "Backups are encrypted and stored in a compressed archive file (.tar) and by default, stored locally in the `/backup` directory." and "The backup stored on Home Assistant Cloud is always encrypted." Note the download behaviour though: "When downloading the backup from the Home Assistant backup page, it is decrypted on the fly so that you can view the data using your favorite archive tool." A downloaded backup is a plaintext tarball. Handle exports accordingly: keep the encryption key from the emergency kit safe, do not put downloaded backups in shared storage, and rotate the tokens above if one leaks.

## Customizing your environment

Three persistent hooks let you tune the shell, tmux, and container startup without editing anything inside the container:

### `/config/claude-config/bashrc.local`
Shell aliases, env vars, functions, PS1 tweaks. Sourced by every interactive bash session on top of the defaults.

```bash
alias k=kubectl
export EDITOR=vim
export PROMPT_COMMAND='history -a'
```

### `/config/claude-config/tmux.conf.local`
tmux overrides. Sourced by the default `~/.tmux.conf` if the file exists.

```tmux
set -g status on
bind r source-file ~/.tmux.conf \; display "Reloaded!"
```

### `/config/claude-config/init.sh`
Runs once at container boot, from `run.sh`, in a subshell. An `exit` inside the hook cannot abort the boot, but that also means **exports inside `init.sh` do not propagate** to the rest of the container. Use it for custom symlinks, one-off setup, background helpers. Use `bashrc.local` for anything that needs to export an env var. A non-zero exit is logged and ignored.

```bash
#!/bin/bash
ln -sfn /config/claude-config/my-stuff /root/.my-stuff
```

### Claude Code versions
Run `claude install X.Y.Z` inside the terminal to install a specific version. It writes to `/config/claude-config/claude-installations/versions/` and sticks across restarts. On every boot the newest installed version is activated unless `claude_version` pins one. Versions beyond the newest two (plus the active one) are pruned at boot.

## What ships in the container

- **Claude Code**, installed via Anthropic's native installer at a pinned version (see `CHANGELOG.md`). That pin is only the starting point: the install dir is persisted, so the auto-updater and `claude install` both stick.
- **Bun**, needed by some plugin runtimes (the official Telegram channel among them).
- **Node.js + npm** for general dev work. Not required by Claude itself.
- **git, github-cli, openssh-client** for working with repos.
- **tmux** keeps the session alive across browser closes.
- **ttyd** is the web terminal. Its binary is checksum-verified against the upstream release at build time.
- **ripgrep, jq, python3, nano, tree, qrencode**.
- **ha-check, ha-restart, ha-notify, claude-login**: the helpers above.

## Architectures supported

`amd64` and `aarch64`. That covers NUCs, mini PCs, Raspberry Pi 4 and 5.

`armv7` (Pi 3 and older) is not supported: Bun ships no Linux armv7 build, and Bun is needed by the Telegram channel plugin and other plugins.

## Security

**Who can open it.** The add-on is restricted to Home Assistant admin users (`panel_admin: true`). Anyone with admin access to your HA has shell access to your config directory through it.

**Network.** Port 7681 is not published by default; ingress is the only way in, and ingress goes through HA's own login. If you publish port 7681 in the add-on's Network tab, anyone who can reach that port gets an unauthenticated shell. ttyd has no login of its own.

**What the container can reach.** Read/write access to `/config`, and the Home Assistant Core REST API through `homeassistant_api: true`. The Supervisor API is not requested. The read-only `addons` mount that earlier versions had was removed in 2.1.0; nothing used it.

**Default permission deny list.** New installs get a `settings.json` with these rules under `permissions.deny`:

```
Read(//config/secrets.yaml)
Edit(//config/secrets.yaml)
Read(//config/.storage/**)
Edit(//config/.storage/**)
Read(//config/*.db)
Read(//config/*.db-*)
```

The double slash is Claude Code's syntax for an absolute filesystem path (a single leading slash would be relative to the settings file). Per the permissions docs, Read rules are applied on a best-effort basis to the other built-in file tools such as Grep and Glob as well. They do not cover shell commands Claude runs with your approval; `cat /config/secrets.yaml` in a Bash tool call is still on you to decline.

Existing installs are not modified on upgrade. To merge the shipped rules into your current file (with Claude not running, so it does not write over the result):

```bash
cd /config/claude-config && jq --slurpfile d /opt/claude-defaults/settings.json \
  '.permissions.deny = ((.permissions.deny // []) + $d[0].permissions.deny | unique)' \
  settings.json > settings.json.new && mv settings.json.new settings.json
```

**Bots.** See [Running a bot unattended](#running-a-bot-unattended).

## Troubleshooting

**The terminal is blank or stuck.** Refresh the browser; ttyd reattaches to the live tmux session. If that does not help, restart the add-on. ttyd is restarted in place if it dies; five deaths in two minutes make the add-on exit so the watchdog restarts it.

**Claude says "not logged in".** Run `claude /logout`, then `claude` again and log in. Or set `oauth_token`.

**Copy does not work in the HA panel.** Known limitation of the web terminal inside HA's ingress frame, worst in the Companion app. Work around it in this order: click the link instead of copying it (login URLs are clickable, wrapped or not); use `claude-login` from a second tmux window to get the URL as a QR code or in `login-url.txt`; or select the text with the mouse and release the button outside the terminal area, which makes the copy land in some browsers. If you find a combination that works or fails reliably, please report the browser, OS, and whether it was the Companion app in an issue on this repository. Terminal text is rendered as DOM text (not a canvas) since 2.1.0, so selection itself should work in WebViews.

**I cannot click the login URL (Companion app).** Use `claude-login`. See [Logging in](#logging-in).

**Bot keeps restarting / gave up after 5 crashes.** Open the web terminal; the session shows the last restart messages and, if it gave up, a bash prompt. Read `/config/claude-config/logs/current` with `less -R` to see what the command printed before each exit. Typical causes: not logged in (set `oauth_token` or log in interactively), a plugin that failed to start, a Telegram 409 (see below). Fix it, then `exec /opt/tmux-session.sh` in that window or restart the add-on. If you want the command to stay down while you investigate, create `/config/claude-config/no-restart`.

**Pinned version is not installed.** The add-on log says `claude_version X is not installed; run 'claude install X' once from the terminal, then restart` and falls back to the newest installed version. Do exactly that: `claude install X` in the web terminal, then restart the add-on. Check what is installed with `ls /config/claude-config/claude-installations/versions/`.

**Telegram plugin errors with HTTP 409.** A stale Bun process is holding the Telegram polling connection. Restart the add-on.

**An option change does not take effect.** Options are read at container boot. After changing anything in the add-on configuration, restart the add-on. Saving alone is not enough.

**Plugin installs disappear after restart.** They should not. Check that `/config/claude-config/plugins/` exists and has files. If it is empty, the persistent volume is not mounting; check the add-on's `map:` configuration or your HA storage.

**`ha-check` says SUPERVISOR_TOKEN is not set.** You are running the image outside the Supervisor (local docker/podman). The Core API proxy only exists inside HA.

**Something ended up in `migrated/`.** A real file or directory was sitting where the add-on needed to put a symlink (for example an old `/root/.ssh`). It was moved to `/config/claude-config/migrated/<name>.<timestamp>` rather than deleted. Copy out what you need and remove the rest.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) in this directory.
