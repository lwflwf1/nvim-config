return {
    {
        "folke/snacks.nvim",
        priority = 1000,
        lazy = false,
        opts = {
            animate      = { enabled = true                 },
            bigfile      = { enabled = true, notify = false     },
            dashboard    = { enabled = true                 },
            dim          = { enabled = true                 },
            gh           = { enabled = true                 },
            image        = { enabled = true                 },
            lazygit      = { enabled = true                 },
            indent       = { enabled = true, scope = {enabled = false}, animate = { enabled = false } },
            input        = { enabled = true                 },
            notifier     = { enabled = true, timeout = 5000, style = "fancy" },
            picker       = {
                enabled = true,
                sources = {
                    -- RHEL6 trees live behind symlinks (fzf-lua shipped --follow;
                    -- snacks defaults to no-follow) and fzf-lua showed hidden files
                    -- by default — restore both behaviors globally.
                    grep  = { follow = true },
                    files = { follow = true, hidden = true },
                    smart = { follow = true, hidden = true, ignored = true },
                },
                actions = {
                    trouble_open = function(...)
                        return require("trouble.sources.snacks").actions.trouble_open.action(...)
                    end,
                    flash = function(picker)
                        require("flash").jump({
                            pattern = "^",
                            label = { after = { 0, 0 } },
                            search = {
                                mode = "search",
                                exclude = {
                                    function(win)
                                        return vim.bo[vim.api.nvim_win_get_buf(win)].filetype ~= "snacks_picker_list"
                                    end,
                                },
                            },
                            action = function(match)
                                local idx = picker.list:row2idx(match.pos[1])
                                picker.list:_move(idx, true, true)
                            end,
                        })
                    end,
                },
                win = {
                    input = {
                        keys = {
                            ["<a-t>"] = { "trouble_open", mode = { "n", "i" } },
                            ["<a-s>"] = { "flash", mode = { "n", "i" } },
                            ["s"] = { "flash" },
                        },
                    },
                },
            },
            quickfile    = { enabled = true                 },
            scope        = { enabled = true                 },
            scroll       = { enabled = not vim.g.is_rhel6      },
            statuscolumn = { enabled = true                 },
            terminal     = { enabled = true                 },
            toggle       = { enabled = true                 },
            words        = { enabled = true                 },
            zen          = { enabled = true                 },
            styles       = {
                notification = { wo = { wrap = true, winblend = 0 } },
                input        = { row = 0.5 },
            },
        },
        keys = {
            { "<leader>gz", function() Snacks.lazygit() end,                 desc = "Lazygit" },
            { "<M-=>",      function() Snacks.terminal.toggle() end,         desc = "Toggle terminal", mode = { "n", "t" } },
            { "<leader>bd", function() Snacks.bufdelete() end,               desc = "Delete Buffer" },
            { "<leader>z",  function() Snacks.zen() end,                     desc = "Toggle Zen Mode" },
            { "<leader>Z",  function() Snacks.zen.zoom() end,                desc = "Toggle Zoom" },
            { "<leader>un", function() Snacks.notifier.hide() end,           desc = "Dismiss All Notifications" },
            { "<leader>uh", function() Snacks.notifier.show_history() end,   desc = "Notification History" },
            { "<leader>ln", function() Snacks.rename.rename_file() end,      desc = "Rename File" },
            { "]]",         function() Snacks.words.jump(vim.v.count1) end,  desc = "Next Reference",  mode = { "n", "t" } },
            { "[[",         function() Snacks.words.jump(-vim.v.count1) end, desc = "Prev Reference",  mode = { "n", "t" } },
            { "<leader>uu", function() Snacks.picker.undo() end,             desc = "Undo history" },
            { "<leader>u.", function() Snacks.scratch() end,                 desc = "Toggle Scratch Buffer" },
            { "<leader>us", function() Snacks.scratch.select() end,          desc = "Select Scratch Buffer" },
            { "<leader>uP", function() Snacks.profiler.scratch() end,        desc = "Profiler Scratch" },
        },
        init = function()
            _G.dd = function(...)
                Snacks.debug.inspect(...)
            end
            _G.bt = function()
                Snacks.debug.backtrace()
            end
            vim.api.nvim_create_autocmd("User", {
                pattern = "VeryLazy",
                callback = function()
                    Snacks.toggle.option("spell", { name = "Spelling" }):map("<leader>uS")
                    Snacks.toggle.option("wrap", { name = "Wrap" }):map("<leader>uw")
                    Snacks.toggle.option("relativenumber", { name = "Relative Number" }):map("<leader>uL")
                    Snacks.toggle.diagnostics():map("<leader>lD")
                    Snacks.toggle.line_number():map("<leader>ul")
                    Snacks.toggle.option("conceallevel", { off = 0, on = vim.o.conceallevel > 0 and vim.o.conceallevel or 2 }):map("<leader>uc")
                    Snacks.toggle.treesitter():map("<leader>uT")
                    Snacks.toggle.option("background", { off = "light", on = "dark", name = "Dark Background" }):map("<leader>ub")
                    Snacks.toggle.inlay_hints():map("<leader>lz")
                    Snacks.toggle.indent():map("<leader>ug")
                    Snacks.toggle.dim():map("<leader>uD")
                    Snacks.toggle.profiler():map("<leader>up")
                    Snacks.toggle.profiler_highlights():map("<leader>uH")

                    Snacks.toggle.option("hlsearch", { name = "hlsearch" }):map("<leader>ui")

                    vim.ui.input = Snacks.input.input
                    vim.ui.select = Snacks.picker.select
                end,
            })
        end,
    },
}
