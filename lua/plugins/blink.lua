return {
    {
        "saghen/blink.cmp",
        version = "1.*",
        event = { "InsertEnter", "CmdlineEnter" },
        dependencies = {
            "rafamadriz/friendly-snippets",
            "saghen/blink.compat",
            "milanglacier/minuet-ai.nvim",
            "onsails/lspkind.nvim",
        },
        opts = {
            -- On RHEL6 (glibc < 2.18) the prebuilt Rust fuzzy lib cannot run and
            -- blink would retry a github download every start; use the pure Lua
            -- implementation there only.
            fuzzy = vim.g.is_rhel6 and { implementation = "lua" } or nil,
            appearance = {
                use_nvim_cmp_as_default = true,
            },
            keymap = {
                ["<Tab>"] = { "select_next", "fallback" },
                ["<S-Tab>"] = { "select_prev", "fallback" },
                ["<C-l>"] = { "snippet_forward", "fallback" },
                ["<C-h>"] = { "snippet_backward", "fallback" },
                ["<CR>"] = { "accept", "fallback" },
            },

            sources = {
                default = { "lazydev", "lsp", "snippets", "buffer", "path", "minuet", "orgmode" },
                providers = {
                    lazydev = {
                        name = "LazyDev",
                        module = "lazydev.integrations.blink",
                        score_offset = 100,
                    },
                    minuet = {
                        name = "minuet",
                        module = "minuet.blink",
                    },
                    orgmode = {
                        name = "orgmode",
                        module = "blink.compat.source",
                        score_offset = 0,
                    },
                },
            },

            snippets = { preset = "luasnip" },

            completion = {
                documentation = { auto_show = true },
                menu = {
                    draw = {
                        columns = { { "kind_icon", gap = 1, "kind" }, { "label", "label_description", gap = 1 } },
                        components = {
                            kind_icon = {
                                text = function(ctx)
                                    return require("lspkind").symbol_map[ctx.kind] or ""
                                end,
                            },
                        },
                    },
                },
                list = {
                    selection = {
                        preselect = false,
                        auto_insert = true,
                    },
                },
            },

            cmdline = {
                enabled = true,
            },
        },
        config = function(_, opts)
            require("blink.cmp").setup(opts)
        end,
    },
}
