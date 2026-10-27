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
            -- Priority: cursortab prediction > blink menu > tab-out > raw keys.
            local tabout = require("box.tabout")
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

            -- cursortab steps, shared by the <Tab>, <S-Tab> and <Esc> chains.
            -- State comes from the `init` hook in plugins/cursortab.lua, which
            -- records the WHOLE CursortabStateChanged payload in
            -- vim.g.cursortab_status. cursortab exposes no is_visible(), and a
            -- step table without a callable `condition` is rejected outright by
            -- mini.keymap (keymap.lua:657). The tracked state is the CONDITION
            -- only -- it is written from a vim.schedule'd RPC callback, so it
            -- can lag a tick behind reality; accept()'s own return value is
            -- what actually decides whether the chain continues.
            local VISIBLE_STATES = { "HasCompletion", "HasCursorTarget", "StreamingCompletion" }
            local function prediction_visible()
                local st = vim.g.cursortab_status
                if type(st) ~= "table" then return false end
                -- `.state` is the documented field, but do not depend on it
                -- alone: a Go RPC table is not a contract we control, and
                -- trusting one key is what made this report "Idle" forever.
                if vim.tbl_contains(VISIBLE_STATES, st.state) then return true end
                for _, v in pairs(st) do
                    if vim.tbl_contains(VISIBLE_STATES, v) then return true end
                end
                return false
            end
            local function prediction_accept()
                local ok, accepted = pcall(function()
                    return require("cursortab").accept()
                end)
                -- `false` -> mini.keymap keeps asking the following steps;
                -- `""` -> consume the key (accept() already applied the edit)
                return (ok and accepted) and "" or false
            end
            -- No public dismiss(); on_reject() is the daemon's RPC callback for
            -- exactly this (clear the awaiting flag + close all overlays), so
            -- calling it is what the daemon itself would do on a rejection.
            local function prediction_dismiss()
                pcall(function()
                    require("cursortab").on_reject()
                end)
            end

            -- smart <Tab> (normal): accept/jump a cursortab prediction > raw
            -- <Tab> (= <C-i>, jumplist forward). This is where the Cursor
            -- rhythm lives -- jump once, accept once, jump again -- and normal
            -- mode is the only place it makes sense; the insert chain below
            -- handles inline ghost text. Step actions must be FUNCTIONS: a bare
            -- `require("cursortab").accept()` would be called while this table
            -- is built (i.e. at startup), and the plugin is absent on RHEL6.
            keymap.map_multistep("n", "<Tab>", {
                { condition = prediction_visible, action = prediction_accept },
            })

            -- smart <Tab> (insert): cursortab ghost text > blink next > TabOut >
            -- raw.
            keymap.map_multistep("i", "<Tab>", {
                -- accept the AI suggestion first (it beats motion)
                { condition = prediction_visible, action = prediction_accept },
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

            keymap.map_multistep("i", "<c-h>", {
                {
                    condition = blink_menu_visible,
                    action = function() pcall(function() require("blink.cmp").hide() end) end,
                },
                { condition = prediction_visible, action = prediction_dismiss },
            })

            keymap.map_multistep({ "n", "x" }, "<Esc>", {
                { condition = mc.is_active, action = mc.clear },
                { condition = prediction_visible, action = prediction_dismiss },
                { condition = function() return vim.v.hlsearch == 1 end,
                  action = function() vim.cmd("nohlsearch") end },
            })

            -- smart <BS> (insert, other-editors semantics): in a whitespace run
            -- -> eat the WHOLE run (line-start indentation collapses in one
            -- press); else mini.pairs deletes the surrounding pair between
            -- (|) — its own BS would shadow neither here; classic plain BS for
            -- everything else. hungry first: minipairs_bs always returns keys
            -- (never false), so a trailing minipairs step would be unreachable
            keymap.map_multistep("i", "<BS>", { "minipairs_bs" })

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
