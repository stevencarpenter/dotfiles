# M5 system scripts

Replacements for nix-darwin system effects (DFM-51). Every script has a read-only `--check`.
Outputs verified on the personal MacBook on 2026-10-11. No script ran in write mode.

| Nix effect | Script and mode | Verified `--check` output (2026-10-11) |
| --- | --- | --- |
| `system.defaults` (30 keys, trackpad in two domains), screenshots dir, `.metadata_never_index` sentinels | `scripts/mac-defaults.sh --check` (write: no flag, `--no-restart` skips the Dock restart) | 33 lines, all `ok`, exit 0 |
| `launchd.user.agents.maxfiles` | `scripts/launch-agents.sh --check`, `load`, `unload`; plist `home/Library/LaunchAgents/org.carpenter.maxfiles.plist` | `not loaded: org.carpenter.maxfiles`, exit 1; loaded now: `org.nixos.maxfiles`, `com.user.maxfiles` |
| Login shell via `dscl`, stale `launchctl` SHELL | `scripts/login-shell.sh --check`, `--set` | `ok: UserShell = /bin/zsh`, no stale override, exit 0 |
| `environment.variables.EDITOR` | `export EDITOR=nvim` in `home/.config/zsh/profile.d/common-env.zsh` | No script |
| `home.activation.startTilingStack` | `scripts/tiling-reload.sh --check` (write: no flag) | sketchybar service started, AeroSpace running, exit 0 |

nix-darwin restarts only Dock after writing defaults (`/run/current-system/activate`), so `mac-defaults.sh` does the same.
