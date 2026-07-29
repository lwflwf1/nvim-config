return {
    {
        "echasnovski/mini.nvim",
        event = "VeryLazy",
        config = function()
            require("mini.icons").setup()
            require("mini.pairs").setup()
            vim.api.nvim_create_autocmd("FileType", {
                pattern = { "TelescopePrompt", "vim" },
                callback = function() vim.b.minipairs_disable = true end,
            })
            vim.api.nvim_create_autocmd("FileType", {
                pattern = "systemverilog",
                callback = function()
                    require("mini.pairs").map_buf(0, "i", "'", {
                        action = "closeopen",
                        pair = "''",
                        neigh_pattern = "[^%a]",
                    })
                    require("mini.pairs").unmap_buf(0, "i", "`", "``")
                end,
            })

            require("mini.surround").setup({
                n_lines = 10,
                mappings = {
                    add         = "ys",
                    delete      = "ds",
                    replace     = "cs",
                    find        = "",
                    find_left   = "",
                    highlight   = "",
                    suffix_last = "",
                    suffix_next = "",
                },
                search_method = "cover_or_next",
            })
            -- vim.keymap.set("x", "S", [[:<C-u>lua MiniSurround.add("visual")<CR>]], { silent = true })
            vim.keymap.set("n", "yss", "ys_", { remap = true, desc = "Surround line" })

            require("mini.align").setup()

            require("mini.operators").setup({
                evaluate = { prefix = "" },
                exchange = { prefix = "" },
                multiply = { prefix = "" },
                replace  = { prefix = "s" },
                sort     = { prefix = "" },
            })

            require("mini.bracketed").setup({
                file = { suffix = '' },
                comment = { suffix = '' },
                diagnostic = { suffix = '' },
                location = { suffix = '' },
                buffer = { suffix = '' },
            })
        end,
    },
    {
        "folke/ts-comments.nvim",
        event = { "BufReadPre", "BufNewFile" },
        opts = {
            lang = {
                tc = "# %s",
                ralf = "# %s",
            },
        },
    },
    {
        "folke/flash.nvim",
        event = "VeryLazy",
        opts = {
            modes = {
                char = {
                    jump_labels = true,
                },
            },
        },
        keys = {
            { "gj", mode = { "n", "x", "o" }, function() require("flash").jump() end, desc = "Flash" },
            { "S", function() require("flash").treesitter() end, desc = "Flash Treesitter", mode = { "n", "x", "o" } },
            { "R", function() require("flash").treesitter_search() end, desc = "Flash Treesitter Search", mode = { "o", "x" } },
            { "r", function() require("flash").remote() end, desc = "Flash Remote", mode = "o" },
            { "<c-s>", function() require("flash").toggle() end, desc = "Toggle Flash Search", mode = "c" },
        },
    },
    {
        "jake-stewart/multicursor.nvim",
        branch = "1.0",
        event = "VeryLazy",
        config = function()
            local mc = require("multicursor-nvim")
            mc.setup()

            local set = vim.keymap.set

            -- Add or skip cursor above/below the main cursor.
            set({"n", "x"}, "<c-k>",         function() mc.lineAddCursor(-1)  end)
            set({"n", "x"}, "<c-j>",         function() mc.lineAddCursor(1)   end)
            set({"n", "x"}, "<leader><c-k>", function() mc.lineSkipCursor(-1) end)
            set({"n", "x"}, "<leader><c-j>", function() mc.lineSkipCursor(1)  end)

            -- Add or skip adding a new cursor by matching word/selection
            set({"n", "x"}, "<c-n>", function() mc.matchAddCursor(1) end)
            set({"n", "x"}, "<m-n>", function() mc.matchSkipCursor(1) end)
            set({"n", "x"}, "<c-p>", function() mc.matchAddCursor(-1) end)
            set({"n", "x"}, "<m-p>", function() mc.matchSkipCursor(-1) end)

            -- Add and remove cursors with control + left click.
            set("n", "<c-leftmouse>", mc.handleMouse)
            set("n", "<c-leftdrag>", mc.handleMouseDrag)
            set("n", "<c-leftrelease>", mc.handleMouseRelease)

            -- Disable and enable cursors.
            set({"n", "x"}, "<c-q>", mc.toggleCursor)

            -- Mappings defined in a keymap layer only apply when there are
            -- multiple cursors. This lets you have overlapping mappings.
            mc.addKeymapLayer(function(layerSet)

                -- Select a different cursor as the main one.
                layerSet({"n", "x"}, "<up>", mc.prevCursor)
                layerSet({"n", "x"}, "<down>", mc.nextCursor)

                -- Delete the main cursor.
                layerSet({"n", "x"}, "<leader>x", mc.deleteCursor)

                -- Enable and clear cursors using escape.
                layerSet("n", "<esc>", function()
                    if not mc.cursorsEnabled() then
                        mc.enableCursors()
                    else
                        mc.clearCursors()
                    end
                end)
            end)

            -- Customize how cursors look.
            local hl = vim.api.nvim_set_hl
            hl(0, "MultiCursorCursor", { reverse = true })
            hl(0, "MultiCursorVisual", { link = "Visual" })
            hl(0, "MultiCursorSign", { link = "SignColumn"})
            hl(0, "MultiCursorMatchPreview", { link = "Search" })
            hl(0, "MultiCursorDisabledCursor", { reverse = true })
            hl(0, "MultiCursorDisabledVisual", { link = "Visual" })
            hl(0, "MultiCursorDisabledSign", { link = "SignColumn"})
        end
    },
    {
        "folke/which-key.nvim",
        event = "VeryLazy",
        keys = {
            {
                "<C-w>",
                function()
                    require("which-key").show({ keys = "<C-w>", loop = true })
                end,
                desc = "Window commands (hydra)",
            },
        },
        opts = {
            preset = "modern",
            delay = function(ctx) return ctx.plugin and 0 or 200 end,
            icons = {
                mappings = false,
                colors = true,
            },
            spec = {
                { "<leader>",  group = "Leader",         },
                { "<leader>l", group = "LSP",            },
                { "<leader>f", group = "Find",           },
                { "<leader>g", group = "Git",            },
                { "<leader>w", group = "Window",         },
                { "<leader>m", group = "Markdown",       },
                { "<leader>r", group = "Refactor",       },
                { "<leader>p", group = "Print",          },
                { "<leader>t", group = "TODO/Tab/Table", },
                { "<leader>u", group = "UI Toggle",      },
                { "<leader>s", group = "SOS/Sidekick",   },
                { "<leader>b", group = "Buffer",         },
                { "<leader>q", group = "Session",        },
                { "<leader>e", group = "Explorer",       },
                { "<leader>h", group = "Harpoon",        },
                { "<leader>c", group = "Candela",        },
                { "<leader>a", group = "Avante",         },
                { "<leader>z", group = "Zen",            },
                { "g",         group = "Goto",           },
                { "]",         group = "Next",           },
                { "[",         group = "Prev",           },
                { "z",         group = "Folds",          },
            },
            plugins = {
                marks = true,
                registers = true,
                spelling = { enabled = true, suggestions = 20 },
                presets = {
                    operators = true,
                    motions = true,
                    text_objects = true,
                    windows = true,
                    nav = true,
                    z = true,
                    g = true,
                },
            },
            win = {
                border = "rounded",
                wo = { winblend = 10 },
            },
            sort = { "local", "order", "group", "alphanum", "mod" },
            replace = {
                desc = {
                    { "^:%s*", "" },
                    { "<[cC]md>", "" },
                    { "<[sS]ilent>", "" },
                    { "^lua%s+", "" },
                    { "<CR>", "" },
                },
            },
        },
    },
}
