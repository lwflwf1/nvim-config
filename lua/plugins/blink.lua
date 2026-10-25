return {
    {
        "saghen/blink.cmp",
        version = "1.*",
        event = { "InsertEnter", "CmdlineEnter" },
        dependencies = {
            "rafamadriz/friendly-snippets",
            "saghen/blink.compat",
            "onsails/lspkind.nvim",
            "cursortab.nvim",
        },
        opts = {
            -- On RHEL6 (glibc < 2.18) the prebuilt Rust fuzzy lib cannot run and
            -- blink would retry a github download every start; use the pure Lua
            -- implementation there only.
            fuzzy = vim.g.is_rhel6 and { implementation = "lua" } or nil,
            appearance = {
                -- The kitty/Neovide font is the "JetBrainsMono Nerd Font Mono"
                -- variant (NF icons render single-width). 'normal' makes blink
                -- append ctx.icon_gap (a space) after the icon; the kind_icon
                -- text below must include it (the default component did).
                nerd_font_variant = "normal",
            },
            keymap = {
                -- Disabled here on purpose: the smart multistep chains
                -- (mini.keymap, declared below in this spec) own insert-mode
                -- <Tab>/<S-Tab>/<CR>; the tab-out rule engine lives in
                -- lua/box/tabout.lua. Blink's keymaps are buffer-local, so any
                -- Tab/S-Tab/CR entry here (even the "default" preset's) would
                -- shadow that global multistep map.
                ["<Tab>"] = false,
                ["<S-Tab>"] = false,
                ["<CR>"] = false,
                -- Alt+n / Alt+p for snippet jumps: no `fallback` here — blink's
                -- fallback replays the raw key (ESC+n) when unmapped, which would
                -- exit insert mode outside snippets. Also keeps <C-h> free: in
                -- Windows Terminal Shift+BS/Ctrl+H send 0x08 = <C-h>, which would
                -- otherwise jump instead of delete.
                ["<M-n>"] = { "snippet_forward" },
                ["<M-p>"] = { "snippet_backward" },
            },
-- NOTE on cmdline/search: both settings accept `fun(ctx): boolean` and are
            -- re-evaluated on every selection (completion/list.lua:170-175), so
            -- search can be excluded WITHOUT giving it its own keymap — `:` and
            -- the help cmdwin keep blink's cmdline defaults exactly.
            -- Why search is special: the cmdline source is enabled only for
            -- cmdtypes {':','@'} (sources/cmdline/init.lua:26), so search is
            -- served by the `buffer` source alone, which in search returns only
            -- the current buffer's words (is_search_context() -> get_search_bufnrs)
            -- and those are near-unique. With auto_insert on, selecting a
            -- candidate writes it back into the search box (text_edits.lua:49
            -- vim.fn.setcmdline), so `/de` becomes `/desc` -> CmdlineChanged ->
            -- the list re-filters down to that ONE word -> the
            -- `#list.items == 1 -> accept` shortcut at blink/cmp/init.lua:111
            -- fires and the menu vanishes without ever showing. Upstream:
            -- saghen/blink.cmp#2635 (open) asks for exactly this exclusion.
            cmdline = {
                completion = {
                    list = {
                        selection = {
                            preselect = function()
                                return not vim.fn.getcmdtype():match("^[/?]")
                            end,
                            auto_insert = function()
                                return not vim.fn.getcmdtype():match("^[/?]")
                            end,
                        },
                    },
                },
            },

            sources = {
                -- cursortab contributes the AI source here. Only its
                -- single-line `append_chars` travels through blink (that is all
                -- `cursortab/blink.lua` reads); multi-line edits and the
                -- cursor-prediction UI still render in cursortab's own overlay,
                -- so the AI front now lives in two places by design.
                default = { "lazydev", "lsp", "snippets", "buffer", "path", "orgmode", "cursortab" },
                providers = {
                    -- cursortab's documented blink source (README "blink.cmp").
                    -- `enabled` is asserted in cursortab.lua's provider block and
                    -- read by cursortab/blink.lua's `M:enabled()`; listing the
                    -- name in `default` is what actually turns the source on --
                    -- the README only shows `providers`, but blink's enable list
                    -- is `sources.default`.
                    cursortab = {
                        module = "cursortab.blink",
                        name = "cursortab",
                        async = true,
                        -- MUST equal provider.completion_timeout in
                        -- cursortab.lua (20000). The README calls this out; it is
                        -- the value that decides when blink stops waiting and
                        -- shows the menu anyway, so a mismatch would show an empty
                        -- menu and then pop the completion late.
                        timeout_ms = 20000,
                        -- Sits below lazydev (100) and above the plain sources:
                        -- a model suggestion is worth more than a buffer-word
                        -- match but should not outrank a real LSP completion.
                        score_offset = 50,
                    },
                    lazydev = {
                        name = "LazyDev",
                        module = "lazydev.integrations.blink",
                        score_offset = 100,
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
                -- No `keyword.range` on purpose: 'full' would fix the duplicated
                -- suffix but also eats unrelated tails. box/blink_suffix.lua
                -- tests the tail instead (Zed's "replace_suffix").
                documentation = { auto_show = true },
                menu = {
                    draw = {
                        columns = { { "kind_icon", gap = 0, "kind" }, { "label", "label_description", gap = 1 } },
                        components = {
                            kind_icon = {
                                text = function(ctx)
                                    return (require("lspkind").symbol_map[ctx.kind] or "") .. ctx.icon_gap
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

            -- cmdline completions are on by default (blink auto-detects noice)
        },
        config = function(_, opts)
            -- Conditional suffix replacement (Zed's "replace_suffix" idea). Order
            -- does not matter here: the wrapper passes its own 'full' range and
            -- never reads the resolved config.
            require("box.blink_suffix").setup()

            require("blink.cmp").setup(opts)
        end,
    },
}
