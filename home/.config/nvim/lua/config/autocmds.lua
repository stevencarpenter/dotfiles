-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- Always end saved files with a trailing newline; add one on write if missing.
-- Re-asserts fixendofline per-buffer at BufWritePre so nothing (a filetype
-- plugin, editorconfig, or a formatter) can leave a file without a final EOL.
vim.api.nvim_create_autocmd("BufWritePre", {
  group = vim.api.nvim_create_augroup("ensure_final_newline", { clear = true }),
  callback = function(args)
    vim.bo[args.buf].fixendofline = true
  end,
})
