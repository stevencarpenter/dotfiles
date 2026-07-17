-- Disable MD013 (line-length) in markdown linting.
--
-- markdownlint-cli2 has no --disable flag, and nvim-lint runs it over stdin
-- (`markdownlint-cli2 -`), so its config only resolves from nvim's CWD downward
-- — never from the buffer's file up to $HOME. Pass an explicit --config at the
-- bundled markdownlint.yaml so the rule set applies to every markdown buffer
-- regardless of CWD. LazyVim's nvim-lint appends `prepend_args` to the linter
-- args, yielding `markdownlint-cli2 - --config <cfg>`, which cli2 accepts.
return {
  {
    "mfussenegger/nvim-lint",
    optional = true,
    opts = {
      linters = {
        ["markdownlint-cli2"] = {
          prepend_args = { "--config", vim.fn.stdpath("config") .. "/markdownlint.yaml" },
        },
      },
    },
  },
}
