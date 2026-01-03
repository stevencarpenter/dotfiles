-- set leader keys early so plugins and mappings use them
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")
