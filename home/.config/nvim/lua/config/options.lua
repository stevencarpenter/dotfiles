-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

local opt = vim.opt

-- Saving writes the buffer exactly as edited. Formatting and cleanup are
-- explicit operations on <leader>cf, never side effects of :write.
vim.g.autoformat = false

opt.clipboard = "unnamedplus"
opt.cursorline = true
opt.expandtab = true
opt.fixendofline = false
opt.guicursor = "n-v-c:block-Cursor/lCursor,i-ci-ve:ver25,r-cr:hor20,o:hor50"
opt.hidden = true
opt.hlsearch = true
opt.ignorecase = true
opt.shiftwidth = 2
opt.smartcase = true
opt.smartindent = true
opt.tabstop = 2
opt.undofile = true
opt.undolevels = 1000
opt.undoreload = 10000
