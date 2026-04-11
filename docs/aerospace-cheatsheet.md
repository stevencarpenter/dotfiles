# AeroSpace + SketchyBar Cheatsheet

> Config: `~/.config/aerospace/aerospace.toml` | Layouts: `~/.config/aerospace/layouts/`

---

## Modifier Layers

```
alt             AeroSpace     system-wide window management
Ctrl+Space      tmux          terminal multiplexer prefix
Space           Neovim/Vim    editor leader key
Cmd             macOS         system shortcuts (copy, paste, quit)
```

---

## Main Mode — Keybindings

### Navigation

| Keys               | Action                   |
|--------------------|--------------------------|
| `alt-h/j/k/l`      | Focus left/down/up/right |
| `alt-1` .. `alt-9` | Switch to workspace 1–9  |

### Windows

| Keys                           | Action                             |
|--------------------------------|------------------------------------|
| `alt-shift-h/j/k/l`            | Move window left/down/up/right     |
| `alt-shift-1` .. `alt-shift-9` | Move window to workspace (follow)  |
| `alt-f`                        | Toggle fullscreen                  |
| `alt-shift-f`                  | Toggle floating / tiling           |
| `alt-e`                        | Balance all windows to equal sizes |

### Layout

| Keys              | Action                             |
|-------------------|------------------------------------|
| `alt-,`           | Toggle tiling direction (h/v)      |
| `alt-.`           | Toggle accordion direction (h/v)   |
| `alt-shift-space` | Toggle between tiles and accordion |
| `alt-minus`       | Resize smart shrink                |
| `alt-equal`       | Resize smart grow                  |

**Tiles** = all windows visible, splitting screen.
**Accordion** = one window full-size, others behind; navigate with `alt-h/l`.

### Modes

| Keys          | Action             |
|---------------|--------------------|
| `alt-r`       | Enter resize mode  |
| `alt-shift-;` | Enter service mode |

---

## Resize Mode

Enter: `alt-r` | Exit: `esc` or `enter`

| Keys      | Action     |
|-----------|------------|
| `h / l`   | Width -/+  |
| `j / k`   | Height +/- |
| `-` / `=` | Smart -/+  |

---

## Service Mode

Enter: `alt-shift-;` | Exit: `esc`

| Keys | Action                                |
|------|---------------------------------------|
| `r`  | Reload config                         |
| `f`  | Flatten workspace tree (reset layout) |
| `b`  | Balance window sizes                  |
| `5`  | Arrange workspace 5 comms layout      |

---

## Float Rules

These apps auto-float (won't tile): System Settings, 1Password, Raycast, Finder, Calculator, Activity Monitor.

---

## Personal Machine — Workspaces

| #   | Purpose  | Apps (auto-assigned)      |
|-----|----------|---------------------------|
| `1` | Terminal | Ghostty                   |
| `2` | Browser  | Firefox Developer Edition |
| `3` | IDE      | IntelliJ IDEA             |
| `4` | AI       | Claude, LM Studio         |
| `5` | Comms    | Mail, Calendar, Messages  |
| `6` | Gaming   | Steam                     |
| `7` | Notes    | Obsidian                  |
| `8` | Slack    | Slack                     |
| `9` | Editor   | Zed                       |

### Workspace 5 Layout (service mode `5`)

```
┌──────────┬──────────┐
│   Mail   │          │
├──────────┤ Messages │
│ Calendar │          │
└──────────┴──────────┘
```

---

## SketchyBar

### Left — Workspace Indicators

- Numbers 1–9 with app icons from **sketchybar-app-font**
- Focused workspace: green number + brand-colored app icons
- Unfocused: gray icons
- Each workspace is a clickable bracket (number + icons)

### Center — Front App

- Shows the currently focused application name

### Right — Status Group (single bracket)

- **Volume**: mute/unmute icon (orange/gray)
- **WiFi**: connected/disconnected icon (purple/red)
- **Battery**: icon + percentage + time remaining; color shifts green → yellow → red
- **Calendar**: US date format with calendar icon (aqua); **hover for UTC**
- **Clock**: 24h with seconds + timezone (blue); **hover for UTC**

### UTC Popup

Hover over the clock or calendar to see a dropdown with UTC time and date.

---

## Common Workflows

| Goal                    | Keys                                   |
|-------------------------|----------------------------------------|
| Send app to workspace 3 | `alt-shift-3`                          |
| Side-by-side split      | Open 2 windows on same workspace       |
| Deep focus              | `alt-f` (fullscreen), again to restore |
| Fix broken layout       | `alt-shift-;` → `f` (flatten)          |
| Equalize window sizes   | `alt-e`                                |
| Arrange comms grid      | `alt-shift-;` → `5`                    |
| Precise resize          | `alt-r` → `hjkl` → `esc`               |

---

## CLI

```bash
aerospace list-workspaces --all              # all workspaces
aerospace list-workspaces --focused           # current workspace
aerospace list-windows --workspace 1          # windows on workspace 1
aerospace list-windows --all                  # all windows
aerospace reload-config                       # reload from CLI
aerospace balance-sizes                       # equalize windows
aerospace flatten-workspace-tree              # reset layout tree
```
