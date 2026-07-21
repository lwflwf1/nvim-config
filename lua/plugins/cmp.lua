return {
    {
        "hrsh7th/nvim-cmp",
        event = { "InsertEnter", "CmdlineEnter" },
        dependencies = {
            "hrsh7th/cmp-nvim-lsp",
            "hrsh7th/cmp-buffer",
            "hrsh7th/cmp-path",
            "hrsh7th/cmp-cmdline",
            "L3MON4D3/LuaSnip",
            "saadparwaiz1/cmp_luasnip",
            "rafamadriz/friendly-snippets",
            "uga-rosa/cmp-dictionary",
        },
        config = function()
            local cmp = require("cmp")
            local luasnip = require("luasnip")
            require("luasnip.loaders.from_vscode").lazy_load()

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

            local has_words_before = function()
                if vim.bo[0].buftype == "prompt" then
                    return false
                end
                local col = vim.fn.col(".") - 1
                return col > 0 and vim.fn.getline("."):sub(col, col):match("%s") == nil
            end

            cmp.setup({
                snippet = {
                    expand = function(args)
                        luasnip.lsp_expand(args.body)
                    end,
                },
                mapping = cmp.mapping.preset.insert({
                    ["<Tab>"] = cmp.mapping(function(fallback)
                        if cmp.visible() then
                            cmp.select_next_item()
                        elseif luasnip.expand_or_jumpable() then
                            luasnip.expand_or_jump()
                        elseif has_words_before() then
                            cmp.complete()
                        else
                            fallback()
                        end
                    end, { "i", "s" }),
                    ["<S-Tab>"] = cmp.mapping(function(fallback)
                        if cmp.visible() then
                            cmp.select_prev_item()
                        elseif luasnip.jumpable(-1) then
                            luasnip.jump(-1)
                        else
                            fallback()
                        end
                    end, { "i", "s" }),
                    ["<CR>"] = cmp.mapping.confirm({ select = false }),

                    ["<C-e>"] = cmp.mapping.abort(),
                    ["<C-n>"] = cmp.mapping.select_next_item(),
                    ["<C-p>"] = cmp.mapping.select_prev_item(),
                    ["<C-d>"] = cmp.mapping.scroll_docs(4),
                    ["<C-f>"] = cmp.mapping.scroll_docs(-4),
                }),
                sources = cmp.config.sources({
                    { name = "nvim_lsp" },
                    { name = "luasnip" },
                    { name = "buffer" },
                    { name = "path" },
                    { name = "orgmode" },
                    { name = "dictionary" },
                }),
                sorting = {
                    priority_weight = 2,
                    comparators = {
                        require("cmp").config.compare.exact,
                        require("cmp").config.compare.score,
                        require("cmp").config.compare.recently_used,
                        require("cmp").config.compare.kind,
                        require("cmp").config.compare.length,
                        require("cmp").config.compare.order,
                    },
                },
                formatting = {
                    fields = { "kind", "abbr", "menu" },
                    format = function(entry, vim_item)
                        vim_item.menu = ({
                            nvim_lsp = "[LSP]",
                            luasnip = "[Snip]",
                            buffer = "[Buf]",
                            path = "[Path]",
                            dictionary = "[Dict]",
                        })[entry.source.name] or ""
                        return vim_item
                    end,
                },
                window = {
                    completion = cmp.config.window.bordered(),
                    documentation = cmp.config.window.bordered(),
                },
            })

            cmp.setup.cmdline("/", {
                mapping = cmp.mapping.preset.cmdline(),
                sources = { { name = "buffer" } },
            })
            cmp.setup.cmdline("?", {
                mapping = cmp.mapping.preset.cmdline(),
                sources = { { name = "buffer" } },
            })
            cmp.setup.cmdline(":", {
                mapping = cmp.mapping.preset.cmdline(),
                sources = cmp.config.sources({
                    { name = "path" },
                    { name = "cmdline" },
                }),
            })
        end,
    },
}
