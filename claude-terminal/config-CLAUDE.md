# Home Assistant config directory

This is the live configuration of a running Home Assistant install. Changes here take effect on the real system.

## Layout

- `/config/*.yaml`, `/config/packages/`, `/config/custom_components/`: Home Assistant configuration. This is what the user wants help with.
- `/config/claude-config/`: Claude Code's own state (auth, plugins, settings, conversation history). Not Home Assistant config. Leave it alone unless the user asks about Claude itself.
- `/config/.storage/`: Home Assistant's internal registries (entities, devices, dashboards, auth). Managed by the HA UI; never edit or print it.
- `/config/secrets.yaml`: credentials. Never print its contents. Reference values with `!secret name`.
- `/config/home-assistant_v2.db`: the recorder database. Do not read or modify it.

## Rules for editing

1. Before editing `automations.yaml`, `scripts.yaml`, `scenes.yaml`, or `configuration.yaml`, take a backup: ideally an HA backup (Settings > System > Backups), or at least `cp file file.bak-$(date +%s)`.
2. After editing YAML, run `ha-check`. Only run `ha-restart` if it reports valid. Many changes (automations, scripts, scenes, templates) can be reloaded from the HA UI without a restart.
3. Prefer the HA UI or its REST API for entity, device, area, and dashboard changes. Editing `.storage` by hand corrupts registries.
4. Keep the user's existing style (indentation, entity naming). Do not reformat whole files.

## Helpers available in this terminal

- `ha-check`: validate the HA configuration via the Core API. Exit code 0 means valid.
- `ha-restart`: run `ha-check`, then restart Home Assistant Core (asks for confirmation; `-y` to skip).
- `ha-notify "title" "message"`: post a persistent notification to the HA frontend.
- `claude-login`: print (and QR-encode) the last Claude OAuth login URL from the terminal session, for logging in from another device.
