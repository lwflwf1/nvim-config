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
                    down  = "<M-J>", up    = "<M-K>",
                    line_left  = "<M-H>", line_right = "<M-L>",
                    line_down  = "<M-J>", line_up    = "<M-K>",
                },
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

            -- which-key intercepts operator-pending sequences (e.g. "diw") via
            -- getchar, then re-feeds them with nvim_feedkeys(..., "mit").
            -- multicursor's feedkeys-manager records every `t`-flag feed into
            -- _fedKeys and strips matching keys from vim.on_key, so _typed lost
            -- "iw" (stayed "d") and diw/dd broke with multiple cursors.
            -- Skip _fedKeys recording only for which-key's re-feeds; other
            -- `t`-feeds are still recorded. (multicursor's own feeds call the
            -- saved original and never hit this wrapper.)
            do
                local fkm = require("multicursor-nvim.feedkeys-manager")
                local function from_whichkey()
                    local i = 2
                    while true do
                        local info = debug.getinfo(i, "S")
                        if not info then return false end
                        if info.source:find("which-key", 1, true) then return true end
                        i = i + 1
                    end
                end
                local mc_feedkeys = vim.api.nvim_feedkeys
                vim.api.nvim_feedkeys = function(keys, mode, escape)
                    if type(mode) == "string" and mode:find("t", 1, true)
                        and from_whichkey()
                    then
                        return fkm.nvim_feedkeys(keys, mode, escape)
                    end
                    return mc_feedkeys(keys, mode, escape)
                end
                local mc_fn_feedkeys = vim.fn.feedkeys
                vim.fn.feedkeys = function(keys, mode, ...)
                    if type(mode) == "string" and mode:find("t", 1, true)
                        and from_whichkey()
                    then
                        return fkm.nvim_feedkeys(keys, mode, false)
                    end
                    return mc_fn_feedkeys(keys, mode, ...)
                end
            end

            -- yanky's preserve_cursor keeps the main cursor in place after yiw,
            -- but multicursor's secondary re-feed does not restore reliably
            -- (global preserve state is consumed by the main yank). Skip
            -- preserve while any mc cursor exists so main and secondary both
            -- follow native yiw (move to word start).
            do
                local function patch_yanky_preserve()
                    local ok, pc = pcall(require, "yanky.preserve_cursor")
                    if not ok or pc._mc_patched then return end
                    pc._mc_patched = true
                    local orig_yank, orig_on_yank = pc.yank, pc.on_yank
                    pc.yank = function(...)
                        if mc.hasCursors() then return end
                        return orig_yank(...)
                    end
                    pc.on_yank = function(...)
                        if mc.hasCursors() then return end
                        return orig_on_yank(...)
                    end
                end
                patch_yanky_preserve()
                vim.api.nvim_create_autocmd("User", {
                    pattern = "LazyLoad",
                    callback = function(ev)
                        if ev.data == "yanky.nvim" then
                            patch_yanky_preserve()
                        end
                    end,
                })
            end

            local set = vim.keymap.set

            -- Add or skip cursor above/below the main cursor.
            set({"n", "x"}, "<c-k>", function() mc.lineAddCursor(-1)  end)
            set({"n", "x"}, "<c-j>", function() mc.lineAddCursor(1)   end)
            set({"n", "x"}, "<m-Q>", function() mc.lineSkipCursor(-1) end)
            set({"n", "x"}, "<m-q>", function() mc.lineSkipCursor(1)  end)

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
}
