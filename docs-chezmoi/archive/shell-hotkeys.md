# Shell Hotkey Reference

This document summarizes the effective keymaps defined by the dotfiles for interactive shell tooling. It calls out every explicit override and notes when the
upstream defaults continue to apply.

## Zsh (zsh4humans)

* Keyboard layout is explicitly set to the Mac profile so the bindings below follow macOS-oriented modifier naming (for example, Option is treated as
  `Alt`). [See .zshrc lines 51–65](../../home/.config/zsh/.zshrc#L51-L65)
* The right-arrow key accepts the entire autosuggestion instead of a single character, thanks to `forward-char` being set to `accept`.【F:
  home/.config/zsh/.zshrc†L63-L65】

### Custom key bindings

| Keys                       | Action                                                                                         | Notes                                                                                                  |
|----------------------------|------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------|
| `Ctrl+Backspace`, `Ctrl+H` | Delete the previous word via `z4h-backward-kill-word`.                                         | Replaces the usual single-character erase behavior on these keys.【F:home/.config/zsh/.zshrc†L114-L116】 |
| `Ctrl+Alt+Backspace`       | Delete the previous shell word (respecting shell tokenization) with `z4h-backward-kill-zword`. | Provides a zle-aware variant for shell tokens.【F:home/.config/zsh/.zshrc†L114-L116】                    |
| `Ctrl+/`, `Shift+Tab`      | Undo the last command line change.                                                             | Makes undo available from both bindings listed.【F:home/.config/zsh/.zshrc†L118-L118】                   |
| `Alt+/`                    | Redo the last undone change.                                                                   | Complements the undo bindings.【F:home/.config/zsh/.zshrc†L118-L119】                                    |
| `Alt+Left`                 | Change into the previous directory (`z4h-cd-back`).                                            | Uses the directory stack to move backward.【F:home/.config/zsh/.zshrc†L121-L124】                        |
| `Alt+Right`                | Change into the next directory (`z4h-cd-forward`).                                             | Moves forward through the directory history.【F:home/.config/zsh/.zshrc†L121-L124】                      |
| `Alt+Up`                   | Change to the parent directory (`z4h-cd-up`).                                                  | Navigates up one level in the filesystem.【F:home/.config/zsh/.zshrc†L121-L124】                         |
| `Alt+Down`                 | Change into a child directory chosen from the directory stack (`z4h-cd-down`).                 | Speeds up drilling into recently visited children.【F:home/.config/zsh/.zshrc†L121-L124】                |

### Default bindings

Only the bindings shown above are overridden, so all other z4h-provided keymaps remain at their defaults. There are no additional `z4h bindkey` directives
elsewhere in the configuration, which leaves the stock behavior untouched.【F: home/.config/zsh/.zshrc†L114-L124】

## tmux

* The prefix key is remapped from the stock `Ctrl+b` to `Ctrl+Space` by unbinding the former and setting the latter as the global prefix.【F:
  home/.config/tmux/tmux.conf†L1-L3】
* Reloading the configuration continues to use `prefix+r`, with the binding updated so it re-sources the config and displays a confirmation message.【F:
  home/.config/tmux/tmux.conf†L5-L7】

### Custom key bindings

| Keys                                              | Action                                                          | Notes                                                                                                |
|---------------------------------------------------|-----------------------------------------------------------------|------------------------------------------------------------------------------------------------------|
| `prefix+h` / `prefix+j` / `prefix+k` / `prefix+l` | Select the pane to the left, down, up, or right (respectively). | Provides Vim-style pane navigation.【F:home/.config/tmux/tmux.conf†L15-L19】                           |
| `prefix+                                          | `                                                               | Split the current pane vertically (new pane on the right).                                           | Replaces the default `prefix+%` binding, which is explicitly unbound.【F:home/.config/tmux/tmux.conf†L21-L25】
| `prefix+-`                                        | Split the current pane horizontally (new pane below).           | Replaces the default `prefix+"`, which is explicitly unbound.【F:home/.config/tmux/tmux.conf†L21-L25】 |
| `prefix+Ctrl+p` / `prefix+Ctrl+n`                 | Switch to the previous or next window.                          | Adds rapid cycling shortcuts in addition to the defaults.【F:home/.config/tmux/tmux.conf†L27-L29】     |

### Default bindings

Aside from the overrides listed above, no additional pane, window, or session keymaps are changed in the configuration, so the remaining tmux keybindings
continue to follow the built-in defaults (including mouse support and other options that do not affect keymaps).【F: home/.config/tmux/tmux.conf†L1-L66】

## `pacman-browse` alias (fzf)

The `pacman-browse` helper pipes the package list through `fzf` and remaps the Enter key so that selecting an item opens its details in `less` rather than
simply returning the package name. Other `fzf` keybindings are left untouched because no additional `--bind` expressions are provided.【F:
home/.config/zsh/.zshrc†L26-L27】
