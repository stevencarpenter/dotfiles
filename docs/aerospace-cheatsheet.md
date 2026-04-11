# AeroSpace Cheatsheet

## Modifier Layers (no conflicts)

| Modifier | Tool | Context |
|---|---|---|
| `alt` | AeroSpace | Window management (system-wide) |
| `Ctrl+Space` | tmux prefix | Terminal multiplexer (inside terminal) |
| `Space` | Neovim / IdeaVim leader | Editor commands (inside editor) |
| `Cmd` | macOS | System shortcuts |

## Focus

Move focus between tiled windows.

| Keys | Action |
|---|---|
| `alt-h` | Focus left |
| `alt-j` | Focus down |
| `alt-k` | Focus up |
| `alt-l` | Focus right |

## Workspaces

Switch workspaces instantly (no macOS Space animations).

| Keys | Action |
|---|---|
| `alt-1` .. `alt-9` | Switch to workspace 1-9 |
| `alt-shift-1` .. `alt-shift-9` | Move window to workspace 1-9 (and follow) |

## Move Windows

Rearrange windows within the current workspace layout tree.

| Keys | Action |
|---|---|
| `alt-shift-h` | Move window left |
| `alt-shift-j` | Move window down |
| `alt-shift-k` | Move window up |
| `alt-shift-l` | Move window right |

## Layout

| Keys | Action |
|---|---|
| `alt-,` | Toggle tiling direction (horizontal / vertical) |
| `alt-.` | Toggle accordion direction (horizontal / vertical) |
| `alt-f` | Toggle fullscreen |
| `alt-shift-f` | Toggle floating / tiling |
| `alt-shift-space` | Toggle between tiles and accordion layout |

**Tiles vs Accordion:**
- **Tiles** -- all windows visible, splitting the screen
- **Accordion** -- one window fills the space, others stacked behind it; navigate with `alt-h/l`

## Resize

Quick resize from main mode:

| Keys | Action |
|---|---|
| `alt-minus` | Shrink (smart) |
| `alt-equal` | Grow (smart) |

Precise resize mode (`alt-r` to enter, `esc` to exit):

| Keys | Action |
|---|---|
| `h` | Shrink width |
| `l` | Grow width |
| `j` | Grow height |
| `k` | Shrink height |
| `minus` / `equal` | Smart shrink / grow |

## Service Mode

Enter with `alt-shift-;`, exit with `esc`.

| Keys | Action                                        |
|------|-----------------------------------------------|
| `r`  | Reload config                                 |
| `f`  | Flatten workspace tree (fixes broken layouts) |
| `b`  | Balance window sizes                          |
| `5`  | Arrange workspace 5 layout (personal)         |

## Window Rules

These apps automatically float (won't tile):

- System Settings
- 1Password
- Raycast
- Finder
- Calculator
- Activity Monitor

## Personal Machine — Workspace Assignments

| Workspace | Use      | Apps (auto-assigned)         |
|-----------|----------|------------------------------|
| 1         | Terminal | Ghostty                      |
| 2         | Browser  | Firefox Developer Edition    |
| 3         | IDE      | IntelliJ IDEA                |
| 4         | AI       | Claude, LM Studio            |
| 5         | Comms    | Mail, Calendar, Messages     |
| 6         | Gaming   | Steam                        |
| 7         | Notes    | Obsidian                     |
| 8         | Slack    | Slack (needs wide min-width) |
| 9         | Editor   | Zed                          |

## Common Workflows

**Send an app to its workspace:**
Open app, `alt-shift-3` to send to workspace 3, `alt-1` to go back.

**Side-by-side split:**
Open two windows on the same workspace -- they auto-tile.

**Deep focus:**
`alt-f` to fullscreen, `alt-f` again to restore tiling.

**Fix a messed-up layout:**
`alt-shift-;` then `f` to flatten the workspace tree.

## SketchyBar

SketchyBar shows workspace indicators 1-9 at the top. Focused workspace highlights green, others are dimmed. Clicking a workspace number switches to it.

## CLI Reference

```bash
aerospace list-workspaces --all          # List all workspaces
aerospace list-windows --workspace 1     # List windows on workspace 1
aerospace list-windows --all             # List all windows
aerospace reload-config                  # Reload config from CLI
```

## Config Location

`~/.config/aerospace/aerospace.toml`
