# Claude Terminal welcome banner — installed at /etc/profile.d/01-claude-terminal-welcome.sh.
# Shown once per interactive login shell (guarded by CLAUDE_TERMINAL_WELCOMED so
# nested shells and `exec bash -l` after the startup command don't repeat it).
if [[ $- == *i* ]] && [ -z "${CLAUDE_TERMINAL_WELCOMED:-}" ]; then
    export CLAUDE_TERMINAL_WELCOMED=1
    cat <<'BANNER'

  Claude Terminal
  ───────────────
  Type `claude` to start Claude Code. Closing the browser keeps the session
  alive — reopen the add-on to reattach.

  Logging in:
    • Browser OAuth on first run, or `claude-login` to print/QR the login URL
      (run it from a second tmux window: Ctrl+b c; back with Ctrl+b 0).
    • Or set the `oauth_token` (from `claude setup-token`) or `api_key`
      add-on option — no browser needed.

  Home Assistant helpers: ha-check, ha-restart, ha-notify "title" "msg".

  Everything persists in /config/claude-config/:
    • Claude state, plugins, channels, skills, MCP servers, auth
    • SSH keys, git identity, ~/.config, shell history, session log (logs/)
    • Your custom init: bashrc.local, tmux.conf.local, init.sh (see DOCS.md)

  Add-on options: startup_command (auto-run on boot, e.g.
  `claude -c --channels plugin:telegram@claude-plugins-official`),
  oauth_token, api_key, claude_version (pin).

BANNER
fi
