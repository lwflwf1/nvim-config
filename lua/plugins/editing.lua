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

            -- Smart multistep keys: the rule engine lives in box/tabout.lua
            -- (imports nothing), the chains are declared HERE against mini.
            -- Priority: minuet ghost text > blink menu > tab-out > raw keys.
            local tabout = require("box.tabout")
            -- minuet steps shared by the <Tab> and <Esc> chains
            local function minuet_visible()
                local ok, vt = pcall(require, "minuet.virtualtext")
                return ok and vt.action.is_visible()
            end
            local function minuet_accept()
                pcall(function() require("minuet.virtualtext").action.accept() end)
            end
            local function minuet_dismiss()
                pcall(function() require("minuet.virtualtext").action.dismiss() end)
            end
            local function blink_menu_visible()
                local ok, blink = pcall(require, "blink.cmp")
                return ok and blink.is_menu_visible()
            end
            -- same condition mini.keymap's `blink_accept` builtin uses
            local function blink_item_selected()
                local ok, blink = pcall(require, "blink.cmp")
                return ok and blink.is_menu_visible() and blink.get_selected_item() ~= nil
            end
            local mc = require("box.multicursor")
            -- minuet ghost text lives in Insert mode only (cleared on
            -- InsertLeave), so the normal-mode AI preview to dismiss is the
            -- DUET one; virtualtext steps stay in the <Tab> chain
            local function duet_visible()
                local ok, duet = pcall(require, "minuet.duet")
                return ok and duet.action.is_visible()
            end

            -- smart <Tab> (insert): minuet ghost text > blink next > TabOut >
            -- raw.
            keymap.map_multistep("i", "<Tab>", {
                -- accept minuet ghost text first (AI suggestion beats motion)
                { condition = minuet_visible, action = minuet_accept },
                "blink_next",
                { condition = tabout.condition, action = tabout.action },
            })
            keymap.map_multistep("i", "<S-Tab>", {
                "blink_prev",
                -- step back in over a closer (beyond TabOut; no S-Tab there)
                { condition = tabout.back_in_condition, action = function() return "<Left>" end },
                -- VSCode muscle memory: S-Tab in the indent zone dedents (mini
                -- builtin maps it to <C-d> / << per mode); raw S-Tab has no
                -- native behavior
                "decrease_indent",
            })
            -- CR: blink accept (selected item only) > mini.pairs pair expansion
            -- > raw CR. Replaces blink's own `accept+fallback` CR entry, whose
            -- fallback forwarding to minipairs' expr map is the fragile part.
            keymap.map_multistep("i", "<CR>", { "blink_accept", "minipairs_cr" })

            -- CR in cmdline/search is ONE press: accept the selected completion
            -- AND run the line. `blink_accept` needs a second <CR> because a
            -- mini.keymap step only feeds keys after the mapping (its action is
            -- `<Cmd>lua require("blink.cmp").accept()<CR>`), which merely fills
            -- the cmdline; `accept_and_enter` instead feeds the <CR> from the
            -- accept callback, so the updated line runs immediately (accept
            -- itself is vim.schedule'd, so the ordering is safe).
            -- The condition is deliberately the same as `blink_accept` (menu
            -- visible + item selected): a plain CR must stay "run what I typed",
            -- never "run item 1 instead" — that would rewrite `:e foo.lua` into
            -- some other match. `accept_and_enter`, not
            -- `select_accept_and_enter`: with no selection `list.accept()`
            -- returns early and the press would be swallowed.
            keymap.map_multistep("c", "<CR>", {
                {
                    condition = blink_item_selected,
                    action = function()
                        return "<Cmd>lua require('blink.cmp').accept_and_enter()<CR>"
                    end,
                },
                "minipairs_cr",
            })

            -- smart <Esc> (insert): progressive exit — (1) blink completion menu visible
            -- -> hide it and STAY in insert (blink itself never consumes Esc,
            -- so this is the nvim-cmp-community behavior); (2) minuet ghost
            -- text -> dismiss (it auto-hides while the menu is open, so after
            -- (1) the suggestion may reappear for this press to clear);
            -- (3) raw <Esc> -> leave insert mode.
            -- keymap.map_multistep("i", "<Esc>", {
            --     {
            --         condition = blink_menu_visible,
            --         action = function() pcall(function() require("blink.cmp").hide() end) end,
            --     },
            --     { condition = minuet_visible, action = minuet_dismiss },
            -- })

-- smart <Esc> (normal + visual): one progressive exit per press —
            -- (1) extra multicursor cursors -> clear them; (2) minuet duet
            -- preview -> dismiss it (the ghost text is insert-only, cleared on
            -- InsertLeave); (3) search highlight -> :noh; nothing pending ->
            -- raw <Esc> (aborts pending operators etc.)
            -- Supersedes the old <Esc><Esc> combo, which is no longer mapped.
            keymap.map_multistep({ "n", "x" }, "<Esc>", {
                { condition = mc.is_active, action = mc.clear },
                {
                    condition = duet_visible,
                    action = function()
                        pcall(function() require("minuet.duet").action.dismiss() end)
                    end,
                },
                { condition = function() return vim.v.hlsearch == 1 end,
                  action = function() vim.cmd("nohlsearch") end },
            })

            -- smart <BS> (insert, other-editors semantics): in a whitespace run
            -- -> eat the WHOLE run (line-start indentation collapses in one
            -- press); else mini.pairs deletes the surrounding pair between
            -- (|) — its own BS would shadow neither here; classic plain BS for
            -- everything else. hungry first: minipairs_bs always returns keys
            -- (never false), so a trailing minipairs step would be unreachable
            keymap.map_multistep("i", "<BS>", { "hungry_bs", "minipairs_bs" })

            require("mini.move").setup({
                mappings = {
                    left  = "<M-H>", right = "<M-L>",
                    down  = "<M-J>", up    = "<M-K>",
                    line_left  = "<M-H>", line_right = "<M-L>",
                    line_down  = "<M-J>", line_up    = "<M-K>",
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
            vim.keymap.set("n", "<leader>ps", function() require("box.sessions").save() end,
                { desc = "Save Session" })
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
            vim.keymap.set("n", "<leader>pc", function() require("box.sessions").pick_read() end,
                { desc = "Select Session" })
            vim.keymap.set("n", "<leader>pd", function()
                -- force: allow deleting the currently loaded session (mini clears
                -- v:this_session, so autowrite won't recreate it on exit)
                sessions.select("delete", { force = true })
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
            { "M", mode = { "n", "x", "o" }, function() require("flash").jump() end, desc = "Flash" },
            -- { "<M-K>", mode = { "n" }, function()
            --     require("flash").jump({
            --         action = function(match)
            --             local bufnr = vim.api.nvim_win_get_buf(match.win)
            --             local line = vim.api.nvim_buf_get_lines(bufnr, match.pos[1] - 1, match.pos[1], false)[1] or ""
            --             vim.lsp.buf_request(bufnr, "textDocument/hover", function(client)
            --                 local p = vim.lsp.util.make_position_params(match.win, client.offset_encoding)
            --                 p.position = {
            --                     line = match.pos[1] - 1,
            --                     character = vim.str_utfindex(line, client.offset_encoding, match.pos[2]),
            --                 }
            --                 return p
            --             end, require("noice.lsp.hover").on_hover)
            --         end,
            --     })
            -- end, desc = "Flash hover" },
            { "S", function() require("flash").treesitter() end, desc = "Flash Treesitter", mode = { "n" } },
            { "s", function() require("flash").treesitter() end, desc = "Flash Treesitter", mode = { "o" } },
            { "R", function() require("flash").treesitter_search() end, desc = "Flash Remote Treesitter", mode = { "o", "x" } },
            { "r", function() require("flash").remote() end, desc = "Flash Remote", mode = "o" },
            { "<c-s>", function() require("flash").toggle() end, desc = "Toggle Flash Search", mode = "c" },
        },
    },
}
