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
