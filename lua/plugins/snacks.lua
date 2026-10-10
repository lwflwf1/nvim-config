local project = require("project")

-- fff's indexed engine is used only inside a recognised project
-- (project.get_root(0)); outside one the pickers fall back to snacks' native rg.
-- vim.g.fff_mode == "off" disables fff entirely.

-- Root for the fff index, or nil when outside a project (-> native fallback).
-- get_root() = the manual pin (<leader>pp) when set, else the detected root.
local function fff_root()
    return project.get_root(0)
end

-- ============== fff-powered sources (Rust in-memory index) ==============
-- Engine: require("fff").file_search/content_search (see plugins/fff.lua).
-- Sync FFI calls from the finder coroutine; typical query <10ms against the
-- resident index (time_budget_ms=150 caps the worst-case grep).
--
-- Cold-start handling: fff's index initialises lazily and re-roots run on a
-- background thread, so the first query after startup/a project switch can
-- be empty. Instead of falling back to rg, we poll inside the finder's async
-- coroutine (ctx.async:sleep — non-blocking) and stream results in as soon
-- as the index is ready; a new keystroke aborts the poll automatically.

local fff_grep_mode = "regex"
local FFF_GREP_MODES = { "regex", "plain", "fuzzy" }

-- One-line hint shown as the input window's winbar (above the prompt). The mode
-- word mirrors fff_grep_mode; refreshed when the picker opens and on <a-r>.
local function fff_grep_hint()
    local label = fff_grep_mode:sub(1, 1):upper() .. fff_grep_mode:sub(2)
    return " " .. label .. " · <a-r> mode · *.sv · dir/ · !dir"
end

-- Push the current hint onto a live picker's input winbar (and the layout's
-- cached win opts so a layout rebuild keeps it).
local function fff_set_hint(picker)
    local text = fff_grep_hint()
    local w = picker.layout and picker.layout.wins and picker.layout.wins.input
    if not w then return end
    w.opts.wo.winbar = text
    local wo = picker.layout.win_opts and picker.layout.win_opts.input
    if wo and wo.wo then wo.wo.winbar = text end
    if w.win and vim.api.nvim_win_is_valid(w.win) then
        vim.wo[w.win].winbar = text
    end
end

-- While polling, wake every POLL_MS up to POLL_TRIES times (~6s).
local FFF_POLL_MS = 350
local FFF_POLL_TRIES = 17

-- Canonical form, for comparing a path with the Rust-side picker root.
-- Mirrors fff's ensure_indexed.canon: resolve the real path (Windows 8.3 short
-- names, symlinks) so it matches the Rust side's dunce::canonicalize base_path.
local function fff_norm(p)
    local abs = vim.fn.fnamemodify(vim.fn.expand(p), ":p"):gsub("[/\\]+$", "")
    local ok, real = pcall(function() return vim.uv.fs_realpath(abs) end)
    if ok and real then abs = real end
    local n = vim.fs.normalize(abs)
    if vim.fn.has("win32") == 1 then n = n:lower() end
    return n
end

-- Root held by the Rust picker (nil before it is initialised).
local function fff_rust_root()
    local ok, h = pcall(require("fff.rust").health_check)
    if ok and type(h) == "table" and h.file_picker then
        return h.file_picker.base_path
    end
end

-- Last target confirmed ready and when. health_check runs a git discover, so
-- cache the result instead of re-checking on every keystroke.
local fff_ready_root, fff_ready_at = nil, 0
local FFF_READY_TTL_MS = 2000

-- True when the Rust index is rooted at `target`; otherwise request the
-- background re-root and report not-ready so the caller polls instead of
-- returning the previous project's files.
local function fff_root_ready(target)
    local now = vim.uv.hrtime() / 1e6
    if fff_ready_root and now - fff_ready_at < FFF_READY_TTL_MS and fff_norm(fff_ready_root) == fff_norm(target) then
        return true
    end
    local root = fff_rust_root()
    if root and fff_norm(root) == fff_norm(target) then
        fff_ready_root, fff_ready_at = target, now
        return true
    end
    fff_ready_root = nil
    pcall(require("fff").change_indexing_directory, target)
    return false
end

-- Returns snacks items for a fff file_search query (max 200).
local function fff_files(q, target)
    if not target or not fff_root_ready(target) then return {} end
    local ok, res = pcall(require("fff").file_search, q, {
        max_results = 200,
        wait_for_index_ms = 0,
        cwd = target,
    })
    local items = {}
    if ok and res.items then
        local canon = require("fff.utils").canonicalize_fff_path
        for _, it in ipairs(res.items) do
            if it.type == "file" then
                local abs = canon(it.relative_path)
                if abs then
                    items[#items + 1] = { file = abs, text = abs }
                end
            end
        end
    end
    return items
end

local function fff_grep(q, target)
    if not target or not fff_root_ready(target) then return {} end
    local ok, res = pcall(require("fff").content_search, q, {
        page_size = 200,
        mode = fff_grep_mode,
        trim_whitespace = false,
        wait_for_index_ms = 0,
        cwd = target,
    })
    local items = {}
    if ok and res.items then
        local canon = require("fff.utils").canonicalize_fff_path
        for _, m in ipairs(res.items) do
            local abs = canon(m.relative_path)
            if abs then
                -- fff match_ranges are 0-based end-exclusive ranges; snacks wants
                -- 1-based columns, one entry per matched char (SnacksPickerMatch
                -- highlights a single byte per position). Expand, and use nil when
                -- empty so snacks' regex fallback still applies.
                local positions = {}
                for _, r in ipairs(m.match_ranges or {}) do
                    for i = (r[1] or 0) + 1, (r[2] or 0) do
                        positions[#positions + 1] = i
                    end
                end
                items[#items + 1] = {
                    file = abs,
                    text = abs,
                    -- fff: line 1-based, col 0-based byte offset — identical to snacks pos
                    pos = { m.line_number, m.col },
                    line = m.line_content or "",
                    positions = #positions > 0 and positions or nil,
                }
            end
        end
    end
    return items
end

-- Wrap a snapshot query: when it has results, return them as a plain table
-- (fast path). When empty (index still warming up), return an async generator
-- that sleeps between retries and streams results in; snacks aborts it on the
-- next keystroke / picker close via ctx.async.
--
-- The target root is captured at pick time in `opts.fff_root` (stable across
-- retries and :resume) so the finder never re-derives it from the current buffer.
local function fff_polling_finder(query_fn)
    return function(opts, ctx)
        local q = ctx.filter.search
        local root = opts.fff_root
        -- no captured root -> fail fast instead of burning the 6s poll loop
        if not root then return {} end
        local items = query_fn(q, root)
        if #items > 0 then return items end

        return function(cb)
            local async = ctx.async
            local function poll() return query_fn(q, root) end
            for _ = 1, FFF_POLL_TRIES do
                if not async or not async:running() then return end
                async:sleep(FFF_POLL_MS) -- non-blocking; raises on abort
                local got = async:schedule(poll)
                if #got > 0 then
                    for _, item in ipairs(got) do cb(item) end
                    return
                end
            end
        end
    end
end

local fff_file_finder = fff_polling_finder(fff_files)

local fff_grep_polling = fff_polling_finder(fff_grep)
local fff_grep_finder = function(opts, ctx)
    -- empty query has no grep meaning; don't hand it to fff
    if ctx.filter.search == "" then return {} end
    return fff_grep_polling(opts, ctx)
end

local function fff_cycle_grep_mode(picker)
    local next_idx = 1
    for i, m in ipairs(FFF_GREP_MODES) do
        if m == fff_grep_mode then next_idx = (i % #FFF_GREP_MODES) + 1 end
    end
    fff_grep_mode = FFF_GREP_MODES[next_idx]
    fff_set_hint(picker)
    picker:find({ refresh = true })
end

local function fff_jump_file(picker, item, step)
    local items = picker:items()
    if not item or not item.idx then return end
    for i = item.idx + step, step > 0 and #items or 1, step do
        if items[i] and items[i].file ~= item.file then
            picker.list:_move(i, true, true)
            return
        end
    end
end

local fff_file_source = {
    finder = fff_file_finder,
    format = "file",
    title = "fff file",
    live = true,
    supports_live = true,
}

-- The input must be 2 rows tall for the winbar to render (nvim drops a winbar
-- on a 1-row float), so grow the input child in the resolved layout tree.
local function fff_grep_layout(l)
    local function walk(node)
        for _, c in ipairs(node) do
            if c.win == "input" then c.height = (c.height or 1) + 1
            elseif c.box then walk(c) end
        end
    end
    walk(l.layout)
    return l
end

local fff_grep_source = {
    finder = fff_grep_finder,
    format = "file",
    title = "fff grep",
    live = true,
    supports_live = true,
    -- fff already matched AND ordered the results, so skip snacks' re-sort
    -- (O(n log n) per keystroke) and keep fff's streaming order.
    sort = false,
    -- Only disable the *bonus* scorers (pointless for pre-filtered results).
    -- Do NOT touch fuzzy/regex/smartcase/ignorecase: the matcher also does the
    -- regex/fuzzy filtering and supplies highlight positions — turning it into a
    -- plain substring filter would drop every regex/fuzzy hit (their match text
    -- does not contain the raw query, e.g. `class.*packet` -> `class dsi_top_packet`).
    matcher = {
        sort_empty = false,
        filename_bonus = false,
        file_pos = false,
        cwd_bonus = false,
        frecency = false,
        history_bonus = false,
    },
    actions = {
        fff_mode = function(picker) fff_cycle_grep_mode(picker) end,
        fff_next_file = function(picker, item) fff_jump_file(picker, item, 1) end,
        fff_prev_file = function(picker, item) fff_jump_file(picker, item, -1) end,
    },
    layout = { config = fff_grep_layout },
    on_show = fff_set_hint,
    win = {
        input = {
            wo = { winbar = fff_grep_hint() },
            keys = {
                ["<a-r>"] = { "fff_mode", mode = { "i", "n" }, desc = "Cycle grep mode" },
                ["<a-n>"] = { "fff_next_file", mode = { "i", "n" }, desc = "Next file" },
                ["<a-p>"] = { "fff_prev_file", mode = { "i", "n" }, desc = "Prev file" },
            },
        },
    },
}

-- ============== end fff sources ==============

-- Pickers route through these: fff's indexed engine inside a project, snacks'
-- native rg everywhere else (or when vim.g.fff_mode == "off"). The root is
-- captured here and frozen into the picker opts (`fff_root`), so a mid-pick
-- project switch (or :resume) can't re-root the index out from under the finder.
local function fff_root_enabled()
    return ((vim.g.fff_mode or "project") ~= "off") and fff_root() or nil
end

local function pick_files()
    local root = fff_root_enabled()
    if root then
        Snacks.picker.pick(vim.tbl_extend("force", fff_file_source, { fff_root = root }))
    else
        Snacks.picker.files()
    end
end

local function pick_grep(seed)
    local root = fff_root_enabled()
    if root then
        Snacks.picker.pick(vim.tbl_extend("force", fff_grep_source, { fff_root = root, search = seed }))
    else
        Snacks.picker.grep({ search = seed })
    end
end

local function pick_grep_word()
    local root = fff_root_enabled()
    local search = function(picker) return picker:word() end
    if root then
        Snacks.picker.pick(vim.tbl_extend("force", fff_grep_source, { fff_root = root, search = search }))
    else
        Snacks.picker.grep({ search = search })
    end
end

function _G.grep_textobj()
    local start_pos = vim.api.nvim_buf_get_mark(0, '[')
    local end_pos = vim.api.nvim_buf_get_mark(0, ']')
    local lines = vim.api.nvim_buf_get_lines(0, start_pos[1]-1, end_pos[1], false)
    if #lines == 0 then return end
    if #lines == 1 then
        lines[1] = string.sub(lines[1], start_pos[2]+1, end_pos[2])
    else
        lines[1] = string.sub(lines[1], start_pos[2]+1)
        lines[#lines] = string.sub(lines[#lines], 1, end_pos[2])
    end
    local search = lines[1]:gsub("^%s*(.-)%s*$", "%1")
    if search == "" then
        local text = table.concat(lines, '\n')
        search = text:sub(1, 80)
    end
    if search ~= "" then pick_grep(search) end
end

vim.keymap.set('n', '<leader>fo', function()
    vim.o.operatorfunc = "v:lua.grep_textobj"
    vim.cmd('normal! g@')
end, { noremap = true, silent = true, desc = "Grep text object" })

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
            picker       = {
                enabled = true,
                sources = {
                    -- RHEL6 trees live behind symlinks (fzf-lua shipped --follow;
                    -- snacks defaults to no-follow) and fzf-lua showed hidden files
                    -- by default — restore both behaviors globally.
                    grep  = { follow = true },
                    files = { follow = true, hidden = true },
                    smart = { follow = true, hidden = true, ignored = true },
                    explorer = {
                        -- file watcher is unreliable on RHEL6 NFS trees (cf. snacks.scroll)
                        watch = not vim.g.is_rhel6,
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
            scroll       = { enabled = not vim.g.is_rhel6 and not vim.g.neovide, animate = { easing = "outCubic" } },
            statuscolumn = { enabled = true                 },
            terminal     = { enabled = true                 },
            toggle       = { enabled = true                 },
            words        = { enabled = true                 },
            zen          = { enabled = true                 },
            styles       = {
                notification         = { border = "solid", wo = { wrap = true, winblend = 0 } },
                notification_history = {
                    border = "none",
                    wo = { winbar = "%=%#SnacksNotifierHistoryTitle# Notification History %=" },
                },
                input                = { row = 0.5 },
            },
        },
        config = function(_, opts)
            require("snacks").setup(opts)
            -- Picker windows only remap NormalFloat in their winhl, so cells
            -- whose group has no bg fall back to the window's Normal (not
            -- remapped) and would show the editor bg. Remap Normal per window;
            -- the two source groups that carry the editor bg explicitly
            -- (NonText/LineNr, see onedarkpro's editor.lua) are made
            -- transparent below so everything they feed also falls back.
            local picker_hl = require("snacks").picker.highlight
            local orig_winhl = picker_hl.winhl
            picker_hl.winhl = function(prefix, links)
                local ret = orig_winhl(prefix, links)
                -- the box window already maps Normal:SnacksNormal, and
                -- SnacksNormal links to NormalFloat, so it needs no remap
                if prefix ~= "SnacksPickerBox" then
                    ret = ret .. ",Normal:" .. prefix
                end
                return ret
            end
            local function raw(group)
                return vim.api.nvim_get_hl(0, { name = group })
            end
            -- follow links manually: nvim_get_hl(link = false) resolves through
            -- the current window's winhighlight, which corrupts resolution
            -- while a picker window is focused
            local function resolved(group, attr)
                local h = raw(group)
                local seen = {}
                while h.link and not seen[h.link] do
                    seen[h.link] = true
                    h = raw(h.link)
                end
                return h[attr] and ("#%06x"):format(h[attr]) or nil
            end
            local function fix_picker_hl()
                local float_bg = resolved("NormalFloat", "bg")
                local title_fg = resolved("Title", "fg")
                -- notifier history winbar (not a picker window, so the winhl
                -- remaps above don't apply there)
                Snacks.util.set_hl({
                    SnacksTitle  = { fg = title_fg, bg = float_bg },
                    SnacksFooter = { fg = title_fg, bg = float_bg },
                }, { managed = false })
                -- strip the editor bg from the two source groups (keep fg and
                -- other attrs): the editor looks identical (fallback = Normal
                -- bg) and every group linking them now falls back to the
                -- window's float bg
                for _, name in ipairs({ "LineNr", "NonText" }) do
                    local h = raw(name)
                    h.bg = nil
                    vim.api.nvim_set_hl(0, name, h)
                end
                -- the one group linking Normal: winhl remaps happen before
                -- link resolution, so the Normal: remap above can't reach it;
                -- flatten to fg only and let the bg fall back
                vim.api.nvim_set_hl(0, "SnacksPickerIconFile", { fg = resolved("Normal", "fg") })
            end
            vim.api.nvim_create_autocmd("ColorScheme", { callback = function() vim.schedule(fix_picker_hl) end })
            fix_picker_hl()
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
            { "<leader>li", function() require("config.lsp").pick_config() end, desc = "LSP config (snacks)" },
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
