return {
    {
        "echasnovski/mini.nvim",
        event = "VeryLazy",
        config = function()
            require("mini.pairs").setup()
            vim.api.nvim_create_autocmd("FileType", {
                pattern = { "TelescopePrompt", "vim" },
                callback = function() vim.b.minipairs_disable = true end,
            })
            vim.api.nvim_create_autocmd("FileType", {
                pattern = "rust",
                callback = function()
                    vim.keymap.set("i", "'", "'", { buffer = true })
                    require("mini.pairs").map_buf(0, "i", "<", {
                        action = "open",
                        pair = "<>",
                        neigh_pattern = "^[%a%d:_]",
                    })
                    require("mini.pairs").map_buf(0, "i", ">", {
                        action = "close",
                        pair = "<>",
                        neigh_pattern = "^[%a%d:_]",
                    })
                end,
            })
            vim.api.nvim_create_autocmd("FileType", {
                pattern = "systemverilog",
                callback = function()
                    vim.keymap.set("i", "'", "'", { buffer = true })
                    vim.keymap.set("i", "`", "`", { buffer = true })
                end,
            })

            require("mini.surround").setup({
                n_lines = 10,
                mappings = {
                    add         = "sy",
                    delete      = "sd",
                    replace     = "sr",
                    find        = "",
                    find_left   = "",
                    highlight   = "",
                    suffix_last = "",
                    suffix_next = "",
                },
                search_method = "cover_or_next",
            })
            -- vim.keymap.set("x", "S", [[:<C-u>lua MiniSurround.add("visual")<CR>]], { silent = true })


            require("mini.align").setup()

            require("mini.operators").setup({
                evaluate = { prefix = "g=" },
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

            local keymap = require("mini.keymap")
            keymap.map_combo("i", "jj", "<BS><BS><Esc>", { delay = 500 })
            keymap.map_combo("t", "jj", "<BS><BS><C-\\><C-n>", { delay = 500 })
            keymap.map_combo({ "n", "x" }, "<Esc><Esc>", function()
                if vim.v.hlsearch == 1 then vim.cmd("nohlsearch") end
            end)

            require("mini.move").setup({
                mappings = {
                    left  = "<M-H>", right = "<M-L>",
                    down  = "<M-N>", up    = "<M-P>",
                    line_left  = "<M-H>", line_right = "<M-L>",
                    line_down  = "<M-N>", line_up    = "<M-P>",
                },
            })

            require("mini.trailspace").setup()

            -- split-resize animation only: snacks.scroll already animates
            -- scrolling (mini's would double up), open/close animate *all*
            -- windows by default (floats included, fighting the picker/notifier
            -- animations), and the cursor animation draws a buffer-wide extmark
            -- (with the same buffer in two windows the flying mark shows in
            -- both -- "two cursors"). RHEL6 skips animations repo-wide.
            require("mini.animate").setup({
                cursor = { enable = false },
                scroll = { enable = false },
                resize = {
                    enable = not vim.g.is_rhel6,
                    timing = require("mini.animate").gen_timing.cubic({ duration = 150, unit = "total" }),
                },
                open = { enable = false },
                close = { enable = false },
            })

            -- named sessions, manual-first: <leader>ps prompts for a name on
            -- the first save, then writes back silently (v:this_session is set
            -- by both read and write); autowrite keeps that one session
            -- updated on exit -- it never creates sessions for other dirs
            require("mini.sessions").setup({ autowrite = true })

            local sessions = require("mini.sessions")
            vim.keymap.set("n", "<leader>ps", function()
                if vim.v.this_session ~= "" then
                    sessions.write(nil)
                else
                    vim.ui.input({ prompt = "Session name: " }, function(name)
                        if name and name ~= "" then
                            sessions.write(name)
                        end
                    end)
                end
                vim.notify("Session saved", vim.log.levels.INFO)
            end, { desc = "Save Session" })
            vim.keymap.set("n", "<leader>pl", function()
                sessions.write(sessions.config.file)
            end, { desc = "Save Local Session" })
            vim.keymap.set("n", "<leader>pr", function()
                local latest = sessions.get_latest()
                if latest then
                    sessions.read(latest)
                else
                    vim.notify("No session available", vim.log.levels.INFO)
                end
            end, { desc = "Restore Latest Session" })
            vim.keymap.set("n", "<leader>pc", function()
                sessions.select("read")
            end, { desc = "Select Session" })
            vim.keymap.set("n", "<leader>pd", function()
                sessions.select("delete")
            end, { desc = "Delete Session" })
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
            { "<M-f>", mode = { "n", "x", "o" }, function() require("flash").jump() end, desc = "Flash" },
            { "<M-K>", mode = { "n" }, function()
                require("flash").jump({
                    action = function(match)
                        local bufnr = vim.api.nvim_win_get_buf(match.win)
                        local line = vim.api.nvim_buf_get_lines(bufnr, match.pos[1] - 1, match.pos[1], false)[1] or ""
                        vim.lsp.buf_request(bufnr, "textDocument/hover", function(client)
                            local p = vim.lsp.util.make_position_params(match.win, client.offset_encoding)
                            p.position = {
                                line = match.pos[1] - 1,
                                character = vim.str_utfindex(line, client.offset_encoding, match.pos[2]),
                            }
                            return p
                        end, require("noice.lsp.hover").on_hover)
                    end,
                })
            end, desc = "Flash hover" },
            { "S", function() require("flash").treesitter() end, desc = "Flash Treesitter", mode = { "n", "x", "o" } },
            { "R", function() require("flash").treesitter_search() end, desc = "Flash Treesitter Search", mode = { "o", "x" } },
            { "r", function() require("flash").remote() end, desc = "Flash Remote", mode = "o" },
            { "<c-s>", function() require("flash").toggle() end, desc = "Toggle Flash Search", mode = "c" },
        },
    },
}
