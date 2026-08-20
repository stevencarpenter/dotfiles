# Capstone across a config tree

Make these exact changes:

1. In `nvim.lua`, set `tabstop` and `shiftwidth` to 4.
2. In `services.toml`, change both `old.internal` hosts to `edge.internal`.
3. In `aliases.yaml`, change all three `kubectl` commands to `k` without changing alias names.
4. In `README.md`, change the status from `migration pending` to `migration complete`.

Practice: `<leader>fF` finds files from the challenge worktree, `<leader>sg` searches text from the
project root, `<leader>H` adds the current file to Harpoon, `<leader>h` opens its menu, and
`<leader>1` through `<leader>9` select entries. Native `:e`, `:b`, `<C-o>`, and the alternate-file
mapping `<leader>bb` are also idiomatic.

Golf target: use a picker or Harpoon for cross-file travel, search plus repeat for each repeated
edit, and no mouse.

## Key reference

| Keys | Action |
| --- | --- |
| `<leader>fF` | find files from the current working directory |
| `<leader>sg` | live-grep text across the project root |
| `<leader>H` | add the current file to Harpoon |
| `<leader>h` | open the Harpoon menu |
| `<leader>1`..`9` | jump to that Harpoon slot |
| `<leader>bb` | switch to the alternate (previous) buffer |
| `<C-o>` | back through the jump list, works across files |
| `cgn` + `.` | change the next search match, then repeat |
