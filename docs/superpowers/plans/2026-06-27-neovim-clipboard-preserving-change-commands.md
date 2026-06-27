# Neovim Clipboard-Preserving Change Commands Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent every standard Neovim change command from overwriting the macOS clipboard.

**Architecture:** Extend the existing black-hole-register keymap pattern in `keymaps.lua`. Keep LazyVim's `clipboard=unnamedplus` integration so yanks and pastes continue to use the macOS clipboard, while `c`, `C`, `s`, and `S` discard replaced text.

**Tech Stack:** Lua, Neovim keymaps, chezmoi

---

### Task 1: Protect change commands

**Files:**
- Modify: `dot_config/nvim/lua/config/keymaps.lua`

- [ ] **Step 1: Run a failing headless mapping check**

Run:

```bash
nvim --clean --headless \
  "+lua dofile('dot_config/nvim/lua/config/keymaps.lua'); for _, mode in ipairs({ 'n', 'x' }) do for _, key in ipairs({ 'c', 'C', 's', 'S' }) do local mapping = vim.fn.maparg(key, mode, false, true); assert(mapping.rhs == '\"_' .. key, mode .. ' ' .. key .. ' is not clipboard-safe') end end" \
  +qa
```

Expected: FAIL with `n c is not clipboard-safe` because no change mappings exist yet.

- [ ] **Step 2: Add the minimal mappings**

Add to `dot_config/nvim/lua/config/keymaps.lua`:

```lua
---@diagnostic disable-next-line: undefined-global
vim.keymap.set({ "n", "v" }, "c", '"_c', { desc = "Change without yanking" })
---@diagnostic disable-next-line: undefined-global
vim.keymap.set({ "n", "v" }, "C", '"_C', { desc = "Change to end of line without yanking" })
---@diagnostic disable-next-line: undefined-global
vim.keymap.set({ "n", "v" }, "s", '"_s', { desc = "Substitute without yanking" })
---@diagnostic disable-next-line: undefined-global
vim.keymap.set({ "n", "v" }, "S", '"_S', { desc = "Substitute line without yanking" })
```

- [ ] **Step 3: Run the headless mapping check again**

Run the command from Step 1.

Expected: exit status 0 with no assertion output.

- [ ] **Step 4: Check formatting and whitespace**

Run:

```bash
stylua --check dot_config/nvim/lua/config/keymaps.lua
git diff --check -- dot_config/nvim/lua/config/keymaps.lua
```

Expected: both commands exit 0.

- [ ] **Step 5: Apply the managed keymap and verify the deployed target**

Run:

```bash
chezmoi apply ~/.config/nvim/lua/config/keymaps.lua
cmp -s dot_config/nvim/lua/config/keymaps.lua ~/.config/nvim/lua/config/keymaps.lua
nvim --clean --headless \
  "+lua dofile(vim.fn.expand('~/.config/nvim/lua/config/keymaps.lua')); for _, mode in ipairs({ 'n', 'x' }) do for _, key in ipairs({ 'c', 'C', 's', 'S' }) do local mapping = vim.fn.maparg(key, mode, false, true); assert(mapping.rhs == '\"_' .. key, mode .. ' ' .. key .. ' is not clipboard-safe') end end" \
  +qa
```

Expected: all commands exit 0 with no assertion output.

- [ ] **Step 6: Commit the implementation**

```bash
git add dot_config/nvim/lua/config/keymaps.lua
git commit -m "fix: preserve clipboard during Neovim changes"
```
