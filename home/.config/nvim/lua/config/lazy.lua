local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = {
    -- ensure mason plugins are available and loaded before LazyVim
    { "mason-org/mason.nvim", lazy = false },
    { "mason-org/mason-lspconfig.nvim", lazy = false },

    -- add LazyVim and import its plugins
    {
      "LazyVim/LazyVim",
      import = "lazyvim.plugins",
      -- ensure mason packages are available *before* LazyVim's LSP module runs
      dependencies = {
        { "mason-org/mason.nvim", lazy = false },
        { "mason-org/mason-lspconfig.nvim", lazy = false },
      },
      -- keep deps minimal here since mason entries are explicit above
    },

    -- import LazyVim extras
    { import = "lazyvim.plugins.extras.lang.typescript" },
    { import = "lazyvim.plugins.extras.lang.json" },
    -- import/override with your plugins
    { import = "plugins" },
  },
  defaults = {
    -- By default, only LazyVim plugins will be lazy-loaded. Your custom plugins will load during startup.
    -- If you know what you're doing, you can set this to `true` to have all your custom plugins lazy-loaded by default.
    lazy = false,
    -- It's recommended to leave version=false for now, since a lot the plugin that support versioning,
    -- have outdated releases, which may break your Neovim install.
    version = false, -- always use the latest git commit
    -- version = "*", -- try installing the latest stable version for plugins that support semver
  },
  install = { colorscheme = { "everforrest" } },
  checker = {
    enabled = true, -- check for plugin updates periodically
    notify = false, -- notify on update
  }, -- automatically check for plugin updates
  performance = {
    rtp = {
      -- disable some rtp plugins
      disabled_plugins = {
        "gzip",
        -- "matchit",
        -- "matchparen",
        -- "netrwPlugin",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})

-- LazyVim writes `lazyvim.json` with a raw `io.open`/`f:write` and no final
-- newline (lazyvim/util/json.lua `M.save`), so the BufWritePre `fixendofline`
-- autocmd in config/autocmds.lua can never reach it — that only governs buffer
-- writes. Every `:LazyExtras` toggle, news dismissal, or schema migration
-- therefore reintroduced a `\ No newline at end of file` diff in this repo.
-- Wrap the writer so the file always lands with exactly one trailing newline.
do
  local ok, json = pcall(require, "lazyvim.util.json")
  if ok then
    local save = json.save
    json.save = function(...)
      local result = save(...)
      local path = LazyVim.config.json.path
      local f = io.open(path, "r")
      if f then
        local data = f:read("*a")
        f:close()
        local fixed = data:gsub("\n*$", "") .. "\n"
        if fixed ~= data then
          f = io.open(path, "w")
          if f then
            f:write(fixed)
            f:close()
          end
        end
      end
      return result
    end
  end
end
