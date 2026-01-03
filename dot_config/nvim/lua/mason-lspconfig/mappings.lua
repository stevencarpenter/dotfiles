-- Shim to ensure `require('mason-lspconfig.mappings')` never errors during startup.
-- It attempts to load the real mappings file from the lazy installation directory. If not found
-- (or it fails to load), it returns a minimal table with get_mason_map() -> { lspconfig_to_package = {} }.

local function try_load_real()
  local ok, stdpath = pcall(vim.fn.stdpath, "data")
  if not ok or not stdpath then
    return nil
  end
  local path = stdpath .. "/lazy/mason-lspconfig.nvim/lua/mason-lspconfig/mappings.lua"
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  f:close()
  local chunk, err = loadfile(path)
  if not chunk then
    return nil
  end
  local ok2, res = pcall(chunk)
  if not ok2 then
    return nil
  end
  -- If the real module returned a table, use it
  if type(res) == "table" then
    return res
  end
  -- Otherwise, some modules return values in package.loaded; attempt to fetch it
  return package.loaded["mason-lspconfig.mappings"]
end

local real = try_load_real()
if real then
  return real
end

local fallback = {
  lspconfig_to_package = {},
  package_to_lspconfig = {},
}

function fallback.get_mason_map()
  return {
    lspconfig_to_package = fallback.lspconfig_to_package,
    package_to_lspconfig = fallback.package_to_lspconfig,
  }
end

function fallback.get_package_from_lspconfig(server)
  return fallback.lspconfig_to_package[server]
end

function fallback.get_lspconfig_from_package(package)
  return fallback.package_to_lspconfig[package]
end

function fallback.get_lspconfig_map()
  return fallback.lspconfig_to_package
end

function fallback.get_package_map()
  return fallback.package_to_lspconfig
end

return fallback
