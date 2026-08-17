local M = {}

local source_action_kinds = {
  "source.fixAll",
  "source.organizeImports",
}

---@param action vim.lsp.CodeAction
---@param kind string
---@return boolean
local function matches_kind(action, kind)
  return action.kind ~= nil and (action.kind == kind or vim.startswith(action.kind, kind .. "."))
end

---@param bufnr integer
---@param entry { action: vim.lsp.CodeAction, client_id: integer }
---@param done fun()
local function apply_action(bufnr, entry, done)
  local client = vim.lsp.get_client_by_id(entry.client_id)
  if client == nil then
    done()
    return
  end

  local function apply(action)
    if action.edit then
      vim.lsp.util.apply_workspace_edit(action.edit, client.offset_encoding)
    end

    if action.command then
      local command = type(action.command) == "table" and action.command or action
      client:exec_cmd(command, { bufnr = bufnr })
    end

    done()
  end

  if not (entry.action.edit and entry.action.command) and client:supports_method("codeAction/resolve") then
    local requested = client:request("codeAction/resolve", entry.action, function(err, resolved_action)
      if err and not (entry.action.edit or entry.action.command) then
        vim.notify(err.message or "Unable to resolve code action", vim.log.levels.WARN)
        done()
        return
      end
      apply(resolved_action or entry.action)
    end, bufnr)

    if requested then
      return
    end
  end

  apply(entry.action)
end

---@param bufnr integer
---@param kind string
---@param done fun()
local function apply_source_actions(bufnr, kind, done)
  local clients = vim.lsp.get_clients({ bufnr = bufnr, method = "textDocument/codeAction" })
  if #clients == 0 then
    done()
    return
  end

  vim.lsp.buf_request_all(bufnr, "textDocument/codeAction", function(client)
    local params = vim.lsp.util.make_range_params(0, client.offset_encoding)
    params.context = {
      diagnostics = {},
      only = { kind },
      triggerKind = vim.lsp.protocol.CodeActionTriggerKind.Invoked,
    }
    return params
  end, function(results)
    local actions = {}
    for client_id, response in pairs(results) do
      for _, action in ipairs(response.result or {}) do
        if not action.disabled and matches_kind(action, kind) then
          table.insert(actions, { action = action, client_id = client_id })
        end
      end
    end

    table.sort(actions, function(left, right)
      if left.client_id == right.client_id then
        return left.action.title < right.action.title
      end
      return left.client_id < right.client_id
    end)

    local index = 0
    local function apply_next()
      index = index + 1
      if actions[index] == nil then
        done()
        return
      end
      apply_action(bufnr, actions[index], apply_next)
    end
    apply_next()
  end)
end

-- 'fixendofline' is off globally so saves stay byte-exact; the final-newline
-- guarantee lives here instead. Trim trailing blank lines, then assert 'eol'
-- so the next write ends the file with exactly one newline. Conform never
-- touches the eol flag (it pads both sides of its diff), so nothing downstream
-- undoes this.
---@param bufnr integer
function M.ensure_single_final_newline(bufnr)
  if vim.bo[bufnr].binary then
    return
  end

  local last = vim.api.nvim_buf_line_count(bufnr)
  while last > 1 and vim.api.nvim_buf_get_lines(bufnr, last - 1, last, true)[1]:match("^%s*$") do
    last = last - 1
  end
  if last < vim.api.nvim_buf_line_count(bufnr) then
    vim.api.nvim_buf_set_lines(bufnr, last, -1, true, {})
  end

  -- An empty buffer stays a zero-byte file; everything else gets a final EOL.
  local only_line_empty = last == 1 and vim.api.nvim_buf_get_lines(bufnr, 0, 1, true)[1] == ""
  if not only_line_empty and not vim.bo[bufnr].endofline then
    vim.bo[bufnr].endofline = true
  end
end

---@param bufnr integer
local function format_and_lint(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  LazyVim.format({ buf = bufnr, force = true })
  M.ensure_single_final_newline(bufnr)

  vim.api.nvim_buf_call(bufnr, function()
    local ok, lint = pcall(require, "lint")
    if ok then
      lint.try_lint()
    end
  end)
end

function M.run()
  local bufnr = vim.api.nvim_get_current_buf()
  local kind_index = 0

  local function apply_next_kind()
    kind_index = kind_index + 1
    local kind = source_action_kinds[kind_index]
    if kind == nil then
      format_and_lint(bufnr)
      return
    end
    apply_source_actions(bufnr, kind, apply_next_kind)
  end

  apply_next_kind()
end

return M
