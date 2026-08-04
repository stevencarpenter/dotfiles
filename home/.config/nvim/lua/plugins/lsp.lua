-- Which darwinConfigurations.<host> nixd loads its option set from.
--
-- personal-mac is the only host this flake declares; a work machine is built by
-- its own external wrapper. Honour an explicit DOTFILES_HOST so a wrapper user
-- can point nixd at their own host name, but never infer a host this flake does
-- not provide (nixd would silently get no darwin options).
local function dotfiles_host()
    local configured = vim.env.DOTFILES_HOST or ""
    if configured ~= "" then
        return configured
    end
    return "personal-mac"
end

local dotfiles_flake = string.format("git+file://%s/.dotfiles", vim.env.HOME)
local dotfiles_root = vim.uv.fs_realpath(vim.env.HOME .. "/.dotfiles")
local darwin_config = string.format(
    "(builtins.getFlake %q).darwinConfigurations.%q",
    dotfiles_flake,
    dotfiles_host()
)

return {
    -- Ensure mason and mason-lspconfig load in the correct order
    {
        "mason-org/mason.nvim",
        opts = {
            ensure_installed = {
                "pyright",
                "ruff",
                "typescript-language-server",
                "lua-language-server",
                "terraform-ls",
                "helm-ls",
                "dockerfile-language-server",
                "yaml-language-server",
                "docker-compose-language-service",
            },
        },
    },
    {
        "mason-org/mason-lspconfig.nvim",
        dependencies = {
            "mason-org/mason.nvim",
        },
        opts = {
            automatic_installation = true,
        },
    },
    {
        "neovim/nvim-lspconfig",
        dependencies = {
            "mason-org/mason.nvim",
            "mason-org/mason-lspconfig.nvim",
        },
        opts = {
            autoformat = true,
            servers = {
                nil_ls = false,
                nixd = vim.fn.executable("nixd") == 1 and {
                    on_new_config = function(new_config, root_dir)
                        if vim.uv.fs_realpath(root_dir) ~= dotfiles_root then
                            return
                        end

                        new_config.settings.nixd.nixpkgs = {
                            expr = darwin_config .. ".pkgs",
                        }
                        new_config.settings.nixd.options = {
                            nix_darwin = {
                                expr = darwin_config .. ".options",
                            },
                            home_manager = {
                                expr = darwin_config
                                    .. ".options.home-manager.users.type.getSubOptions []",
                            },
                        }
                    end,
                    settings = {
                        nixd = {
                            formatting = {
                                command = { "nixfmt" },
                            },
                        },
                    },
                } or false,
                pyright = {},
                ruff = {},
                ts_ls = {},
                lua_ls = {
                    settings = {
                        Lua = {
                            workspace = {
                                checkThirdParty = false,
                            },
                            completion = {
                                callSnippet = "Replace",
                            },
                        },
                    },
                },
                terraformls = {},
                helm_ls = {},
                dockerls = {},
                docker_compose_language_service = {},
                yamlls = {
                    settings = {
                        yaml = {
                            schemaStore = {
                                enable = true,
                                url = "https://www.schemastore.org/api/json/catalog.json",
                            },
                            schemas = {
                                kubernetes = {
                                    "k8s/**/*.yaml",
                                    "k8s/**/*.yml",
                                    "manifests/**/*.yaml",
                                    "manifests/**/*.yml",
                                },
                                ["https://raw.githubusercontent.com/docker/compose/master/compose/config/compose_spec.json"] = {
                                    "docker-compose*.yaml",
                                    "docker-compose*.yml",
                                },
                            },
                        },
                    },
                },
            },
        },
    },
}
