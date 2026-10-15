-- snacks.nvim spec. The fff picker sources and the notifier animation live
-- in config/fff_picker.lua and config/notifier_anim.lua.
local fff_picker = require("box.fff_picker")
local pick_files = fff_picker.pick_files
local pick_grep = fff_picker.pick_grep
local pick_grep_word = fff_picker.pick_grep_word
local notifier_animate_in = require("box.notifier_anim").notifier_animate_in
local input_animate_in = require("box.input_anim").input_animate_in

return {
    {
        "folke/snacks.nvim",
        priority = 1000,
        lazy = false,
        opts = {
            animate      = { enabled = true, fps = 120      },
            bigfile      = { enabled = true, notify = false     },
            dashboard    = { enabled = true                 },
            dim          = { enabled = true                 },
            explorer     = { replace_netrw = true, trash = true },
            gh           = { enabled = true                 },
            image        = { enabled = true                 },
            lazygit      = { enabled = true                 },
            indent       = { enabled = true, scope = {enabled = false}, animate = { enabled = false } },
            input        = { enabled = true                 },
            notifier     = { enabled = true, timeout = 5000, style = "fancy" },
            picker = {
                enabled = true,
                -- No tree guide lines: they are icons, not a toggle
                -- (picker/config/defaults.lua icons.tree). Each slot is 2 cells
                -- wide -- format.lua M.tree gives a non-line ancestor slot a
                -- hardcoded "  ", and the default middle/last are "├╴"/"└╴" --
                -- so they must be replaced by two spaces. "" would collapse the
                -- indent and overlap the levels.
                icons = {
                    tree = { vertical = "  ", middle = "  ", last = "  " },
                },
                sources = {
                    -- RHEL6 trees live behind symlinks (fzf-lua shipped --follow;
                    -- snacks defaults to no-follow) and fzf-lua showed hidden files
                    -- by default — restore both behaviors globally.
                    grep  = { follow = true },
                    files = { follow = true, hidden = true },
                    smart = { follow = true, hidden = true, ignored = true },
                    explorer = {
                        -- files/smart already show hidden files; the explorer is a
                        -- separate source and defaults to hiding them
                        hidden = true,
                        -- file watcher is unreliable on RHEL6 NFS trees (cf. snacks.scroll)
                        watch = not vim.g.is_rhel6,
                        -- upstream disables fuzzy for the tree
                        -- (config/sources.lua: matcher = { sort_empty = false, fuzzy = false }).
                        -- Keep it OFF as `regex`: `matcher.regex` is global, so
                        -- enabling it would reinterpret ^foo$ as real regex anchors
                        -- and break the per-token `^`/`$`/`!`/`'` syntax, and it
                        -- can't be toggled at runtime anyway -- `toggle_regex`
                        -- (<a-r>) writes `picker.opts.regex`, while the matcher
                        -- reads the deep-copied `picker.opts.matcher`
                        -- (core/picker.lua:112 + core/matcher.lua:53), so <a-r>
                        -- is a no-op for this source.
                        --
                        -- fuzzy stays on so partial, scattered recall works
                        -- ("cmt" finds config_manager_thread.sv). Ranking is still
                        -- the explorer's own `sort` field, which only reorders
                        -- within a directory - in a tree the useful half of fuzzy
                        -- is filtering, not ordering. `^foo`, `$foo`, `!foo`,
                        -- `'foo'` and `a | b` all keep working: matcher._prepare
                        -- (core/matcher.lua:310-333) turns fuzzy off per token.
                        matcher = { fuzzy = true, sort_empty = false },
                        -- <CR> on a file asks which window to open in first; dirs
                        -- still toggle. A keymap chain can't be conditional, and
                        -- `confirm` can't be overridden: the explorer source's
                        -- setup force-merges its own actions.confirm after the
                        -- config is resolved (snacks/picker/source/explorer.lua).
                        actions = {
                            pick_win_confirm = function(picker, item, action)
                                if item and not item.dir and not picker.input.filter.meta.searching then
                                    if require("snacks.picker.actions").pick_win(picker, item, action) then
                                        return true -- cancelled at the window prompt
                                    end
                                end
                                return require("snacks.explorer.actions").actions.confirm(picker, item, action)
                            end,
                        },
                        win = { list = { keys = {
                            -- grug-far seeded with the current entry's directory
                            ["<leader>fx"] = "explorer_grug_far",
                            ["<CR>"] = "pick_win_confirm",
                        } } },
                    },
                    -- `lines` uses preview="main": its preview is a float over the
                    -- current window showing the SAME buffer. Two fixes while keeping
                    -- preview="main":
                    --  * clear the float's winbar — nvim copies the buffer's window
                    --    options (winbar) into the new float, so dropbar/lualine render
                    --    a second breadcrumb there;
                    --  * shrink that float to the rows NOT covered by the picker, so the
                    --    preview's `zz` centers the match in the visible window instead
                    --    of the whole (partly overlaid) window.
                    lines = {
                        win = { preview = { wo = { winbar = "" } } },
                        on_show = function(picker)
                            require("snacks.picker.config.sources").lines.on_show(picker)
                            local pv = picker.preview and picker.preview.win and picker.preview.win.win
                            local iw = picker.input and picker.input.win and picker.input.win.win
                            if pv and iw and vim.api.nvim_win_is_valid(pv) and vim.api.nvim_win_is_valid(iw) then
                                local pos_pv = vim.api.nvim_win_get_position(pv)
                                local pos_iw = vim.api.nvim_win_get_position(iw)
                                local vis = pos_iw[1] - pos_pv[1] - 1 -- rows above the picker (minus its border)
                                vim.api.nvim_win_set_config(pv, {
                                    relative = "win",
                                    win = picker.main,
                                    row = 0,
                                    col = 0,
                                    width = vim.api.nvim_win_get_width(pv),
                                    height = math.max(1, vis),
                                })
                                picker:show_preview()
                                picker.preview:show(picker, { force = true })
                            end
                        end,
                    },
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
                    -- Bulk-rename the basenames of the selected files (or the
                    -- cursor item) with a Lua-pattern search/replace pair (`%1`
                    -- for captures). Reuses Snacks.rename.rename_file, which
                    -- falls back to a plain rename when no LSP client supports
                    -- workspace/willRenameFiles. Skips directories, unchanged
                    -- names and targets that already exist (never overwrites).
                    rename_replace = function(picker)
                        local uv = vim.uv or vim.loop
                        local items = picker:selected({ fallback = true })
                        local search = picker.input and picker.input.filter and picker.input.filter.search or ""
                        Snacks.input({ prompt = "Rename pattern (lua): ", default = search }, function(pattern)
                            if not pattern or pattern == "" then
                                return
                            end
                            Snacks.input({ prompt = "Replace with: " }, function(repl)
                                if not repl then
                                    return
                                end
                                local renames, skipped, seen = {}, {}, {}
                                for _, item in ipairs(items) do
                                    local from = Snacks.picker.util.path(item)
                                    local stat = from and uv.fs_stat(from)
                                    if not (from and stat and stat.type == "file") then
                                        skipped[#skipped + 1] = from or "<no file>"
                                    else
                                        local base = vim.fn.fnamemodify(from, ":t")
                                        local newbase = base:gsub(pattern, repl)
                                        local to = vim.fs.dirname(from) .. "/" .. newbase
                                        if newbase == "" or newbase == base then
                                            -- unchanged
                                        elseif uv.fs_stat(to) or seen[to] then
                                            skipped[#skipped + 1] = from .. " (target exists)"
                                        else
                                            seen[to] = true
                                            renames[#renames + 1] = { from = from, to = to }
                                        end
                                    end
                                end
                                if #renames == 0 then
                                    Snacks.notify.warn("rename: nothing to do (" .. #skipped .. " skipped)")
                                    return
                                end
                                local lines = {}
                                for i, r in ipairs(renames) do
                                    if i > 8 then
                                        lines[#lines + 1] = "  ... and " .. (#renames - 8) .. " more"
                                        break
                                    end
                                    lines[#lines + 1] = "  "
                                        .. vim.fn.fnamemodify(r.from, ":t")
                                        .. " -> "
                                        .. vim.fn.fnamemodify(r.to, ":t")
                                end
                                picker:close()
                                local choice = vim.fn.confirm(
                                    "Rename " .. #renames .. " file(s)?\n" .. table.concat(lines, "\n"),
                                    "&Apply\n&Cancel"
                                )
                                if choice ~= 1 then
                                    return
                                end
                                local done, failed = 0, {}
                                for _, r in ipairs(renames) do
                                    Snacks.rename.rename_file({
                                        from = r.from,
                                        to = r.to,
                                        on_rename = function(_, frm, ok)
                                            if ok then
                                                done = done + 1
                                            else
                                                failed[#failed + 1] = frm
                                            end
                                        end,
                                    })
                                end
                                local msg = ("rename: %d/%d done"):format(done, #renames)
                                if #skipped > 0 then
                                    msg = msg .. (", %d skipped"):format(#skipped)
                                end
                                if #failed > 0 then
                                    Snacks.notify.error(
                                        msg .. (", %d failed:\n"):format(#failed) .. table.concat(failed, "\n")
                                    )
                                else
                                    Snacks.notify.info(msg)
                                end
                            end)
                        end)
                    end,
                    explorer_grug_far = function(picker)
                        local prefills = { paths = picker:dir() }
                        local grug_far = require("grug-far")
                        if not grug_far.has_instance("explorer") then
                            grug_far.open({
                                instanceName = "explorer",
                                prefills = prefills,
                                staticTitle = "Find and Replace from Explorer",
                            })
                        else
                            grug_far.get_instance("explorer"):open()
                            grug_far.get_instance("explorer"):update_input_values(prefills, false)
                        end
                    end,
                },
                win = {
                    input = {
                        keys = {
                            ["<a-t>"] = { "trouble_open", mode = { "n", "i" } },
                            ["<a-s>"] = { "flash", mode = { "n", "i" } },
                            ["<a-n>"] = { "rename_replace", mode = { "n", "i" } },
                            ["s"] = { "flash" },
                        },
                    },
                },
            },
            quickfile    = { enabled = true                 },
            scope        = { enabled = true                 },
            -- scroll: on inside Neovide too (smoother G/gg there than Neovide's
            -- own scroll animation, which can't render the middle of a far jump);
            -- Neovide's native scroll animation is disabled in box/neovide.lua
            scroll       = { enabled = not vim.g.is_rhel6, animate = { easing = "outCubic" } },
            statuscolumn = { enabled = true                 },
            terminal     = { enabled = true                 },
            toggle       = { enabled = true                 },
            words        = { enabled = true                 },
            zen          = { enabled = true                 },
            styles       = {
                notification         = {
                    border = "solid",
                    wo = { wrap = true, winblend = 0 },
                    on_win = notifier_animate_in,
                },
                notification_history = {
                    border = "none",
                    wo = { winbar = "%=%#SnacksNotifierHistoryTitle# Notification History %=" },
                },
                input                = { row = 0.5, on_win = input_animate_in },
            },
        },
        config = function(_, opts)
            require("snacks").setup(opts)
            -- Picker-window background patching (winhl + the float-bg fallbacks).
            -- The notifier body groups live in box/hl.lua.
            require("box.picker_hl").setup()
            -- Dashboard `s` opens the session picker instead of mini.sessions.read()
            require("box.dashboard").setup()
        end,
        keys = {
            { "<leader>ee", function() Snacks.explorer() end,                desc = "Explorer (sidebar)" },
            { "<leader>ef", function() Snacks.explorer({ layout = { preset = "vertical" } }) end, desc = "Explorer (float)" },
            { "-",          function() Snacks.explorer.reveal() end,         desc = "Explorer: reveal current file" },
            { "<leader>gz", function() Snacks.lazygit() end,                 desc = "Lazygit" },
            { "<M-=>",      function() Snacks.terminal.toggle() end,         desc = "Toggle terminal", mode = { "n", "t" } },
            { "<M-+>",      function()
                -- Terminal in its own tab. snacks keys terminals by
                -- cmd+cwd+env+count, so a distinct count keeps this one separate
                -- from the <M-=> float; 100+tabnr avoids the user's `N<M-=>`.
                vim.cmd("tabnew")
                Snacks.terminal.open(nil, {
                    count = 100 + vim.api.nvim_tabpage_get_number(0),
                    win = { position = "current", wo = { winbar = "" } },
                })
            end, desc = "Terminal in new tab", mode = { "n", "t" } },
            { "<leader>bd", function() Snacks.bufdelete() end,               desc = "Delete Buffer" },
            { "<leader>ze", function() Snacks.zen() end,                     desc = "Toggle Zen Mode" },
            { "<leader>zo", function() Snacks.zen.zoom() end,                desc = "Toggle Zoom" },
            { "<leader>un", function() Snacks.notifier.hide() end,           desc = "Dismiss All Notifications" },
            { "<leader>uh", function() Snacks.notifier.show_history() end,   desc = "Notification History" },
            { "<leader>ln", function() Snacks.rename.rename_file() end,      desc = "Rename File" },
            { "]]",         function() Snacks.words.jump(vim.v.count1) end,  desc = "Next Reference", mode = { "n", "t" } },
            { "[[",         function() Snacks.words.jump(-vim.v.count1) end, desc = "Prev Reference", mode = { "n", "t" } },
            { "<leader>uu", function() Snacks.picker.undo() end,             desc = "Undo history" },
            { "<leader>u.", function() Snacks.scratch() end,                 desc = "Toggle Scratch Buffer" },
            { "<leader>us", function() Snacks.scratch.select() end,          desc = "Select Scratch Buffer" },
            { "<leader>uP", function() Snacks.profiler.scratch() end,        desc = "Profiler Scratch" },
        },
        init = function()
            -- Same globals are declared in snacks' bundled docs/example files
            -- (indexed as a LuaLS library), hence duplicate-set-field.
            ---@diagnostic disable-next-line: duplicate-set-field
            _G.dd = function(...)
                Snacks.debug.inspect(...)
            end
            ---@diagnostic disable-next-line: duplicate-set-field
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
                    Snacks.toggle.dim():map("<leader>ud")
                    Snacks.toggle.profiler():map("<leader>up")
                    Snacks.toggle.profiler_highlights():map("<leader>uH")

                    Snacks.toggle.option("hlsearch", { name = "hlsearch" }):map("<leader>ui")

                    vim.ui.input = Snacks.input.input
                    vim.ui.select = Snacks.picker.select
                end,
            })
        end,
    },
    {
        "folke/snacks.nvim",
        keys = {
            -- fff-backed in a project, snacks native elsewhere (see pick_* above)
            { "<leader>ff", pick_files, desc = "Find files" },
            { "<leader>fz", function() pick_grep(nil) end, desc = "Live grep" },
            { "<leader>fw", pick_grep_word, mode = { "n", "x" }, desc = "Search current word/selection" },
            { "<leader>fg", function() Snacks.picker.git_files() end, desc = "Find git files" },
            { "<leader>fG", function() Snacks.picker.git_grep() end, desc = "Grep in git files" },
            { "<leader>fm", function() Snacks.picker.recent() end, desc = "Recent files" },
            { "<leader>fu", function() Snacks.picker.lsp_symbols() end, desc = "LSP document symbols" },
            { "<leader>fS", function() Snacks.picker.lsp_symbols({ workspace = true }) end, desc = "LSP workspace symbols" },
            { "<leader>fd", function() Snacks.picker.lsp_references() end, desc = "LSP references" },
            { "<leader>li", function() require("box.lsp").pick_config() end, desc = "LSP config (snacks)" },
            { "<leader>fl", function() Snacks.picker.lines() end, desc = "Buffer line fuzzy search" },
            { "<leader>fL", function() Snacks.picker.grep_buffers() end, desc = "Grep open buffers" },
            { "<leader>fn", function() pick_grep(vim.fn.expand("%:t")) end, desc = "Search current filename in text" },
            { "<leader>fr", function() Snacks.picker.resume() end, desc = "Resume" },
            { "<leader>fb", function() Snacks.picker.buffers() end, desc = "Buffers" },
            { "<leader>fc", function() Snacks.picker.commands() end, desc = "Commands" },
            { "<leader>fh", function() Snacks.picker.command_history() end, desc = "Command history" },
            { "<leader>fq", function() Snacks.picker.qflist() end, desc = "Quickfix" },
            { "<leader>ft", function() Snacks.picker.tags({ workspace = true }) end, desc = "Project tags" },
            { "<leader>fT", function() Snacks.picker.tags({ workspace = false }) end, desc = "Buffer tags" },
            { "<leader>f'", function() Snacks.picker.registers() end, desc = "Registers" },
            { "<leader>f?", function() Snacks.picker.keymaps() end, desc = "Keymaps" },
            { "<leader>fj", function() Snacks.picker.jumps() end, desc = "Jumps" },
            { "<leader>fk", function() Snacks.picker.marks() end, desc = "Marks" },
        },
    },
}
