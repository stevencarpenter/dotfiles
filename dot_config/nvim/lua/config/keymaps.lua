-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

---@diagnostic disable-next-line: undefined-global
vim.keymap.set({ "n", "v" }, "d", '"_d', { desc = "Delete without yanking" })
---@diagnostic disable-next-line: undefined-global
vim.keymap.set({ "n", "v" }, "x", '"_x', { desc = "Delete char without yanking" })
