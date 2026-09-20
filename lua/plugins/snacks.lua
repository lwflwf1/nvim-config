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
