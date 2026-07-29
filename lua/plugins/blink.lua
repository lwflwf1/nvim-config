return {
    {
        "saghen/blink.cmp",
        version = "1.*",
        event = { "InsertEnter", "CmdlineEnter" },
        dependencies = {
            "rafamadriz/friendly-snippets",
            "saghen/blink.compat",
            "uga-rosa/cmp-dictionary",
            "milanglacier/minuet-ai.nvim",
            "onsails/lspkind.nvim",
        },
        opts = {
            appearance = {
                use_nvim_cmp_as_default = true,
            },
            keymap = {
                ["<Tab>"] = { "select_next", "snippet_forward", "fallback" },
                ["<S-Tab>"] = { "select_prev", "snippet_backward", "fallback" },
                ["<CR>"] = { "select_and_accept", "fallback" },

                ["<C-e>"] = { "hide", "fallback" },
                ["<C-n>"] = { "select_next", "fallback" },
                ["<C-p>"] = { "select_prev", "fallback" },
                ["<C-d>"] = { "scroll_documentation_down", "fallback" },
                ["<C-f>"] = { "scroll_documentation_up", "fallback" },
            },

            sources = {
                default = { "lazydev", "lsp", "snippets", "buffer", "path", "minuet", "orgmode", "dictionary" },
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
                    dictionary = {
                        name = "dictionary",
                        module = "blink.compat.source",
                        score_offset = -5,
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
            local dict_paths = {}
            if vim.fn.has("win32") == 1 then
                local win_dict = vim.fn.stdpath("config") .. "\\words"
                if vim.fn.filereadable(win_dict) == 1 then
                    table.insert(dict_paths, win_dict)
                end
            else
                local unix_dicts = { "/usr/share/dict/words", "/usr/dict/words" }
                for _, p in ipairs(unix_dicts) do
                    if vim.fn.filereadable(p) == 1 then
                        table.insert(dict_paths, p)
                    end
                end
            end
            if #dict_paths > 0 then
                require("cmp_dictionary").setup({ paths = dict_paths, exact_length = 2 })
            end

            require("blink.cmp").setup(opts)
        end,
    },
}
