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

-- Windows' default timer resolution is ~15.6ms, which quantizes uv timers to
-- ~15.6ms (measured: an 8ms interval fires at ~15.6ms, and 16ms rounds up to
-- 31ms) and caps the animation at ~64fps. Requesting 1ms resolution via
-- winmm.timeBeginPeriod(1) lets the same timer fire at ~8.5ms, so the
-- animation can run at 120fps. The request is released automatically when the
-- process exits; LuaJIT's ffi is always available in nvim.
if vim.g.os == "windows" then
    pcall(function()
        local ffi = require("ffi")
        ffi.cdef("unsigned int timeBeginPeriod(unsigned int);")
        ffi.load("winmm").timeBeginPeriod(1)
    end)
end

-- Critically-damped spring as an easing curve for Snacks.animate: the closed
-- form of the trajectory the previous per-frame spring integration followed
-- (nvim-notify's animate/spring.lua, damping == 1, velocity 0 at t=0). `t`/`d`
-- are the step index and step count; k = angular_freq * total_duration. k=5.5
-- over 250ms is ~3.5Hz; at 120fps the int-rounded 30-step table has 2-3 cell
-- steps with sub-cell holds at most one 2-frame run (6 holds on a 38-cell
-- width, 2 on a 78-cell one) -- shorter totals keep the holds from running
-- together.
local function spring_easing(t, b, c, d)
    local u = t / d
    return b + c * (1 - (1 + 5.5 * u) * math.exp(-5.5 * u))
end

local function notif_anim_opts(id)
    -- 120fps where the timer supports it (see timeBeginPeriod above; measured
    -- ~8.5ms actual for an 8.33ms request). step=15 keeps small widths
    -- proportional (duration = min(15 * cells, 250)).
    return { id = id, fps = 120, duration = { step = 15, total = 250 }, easing = spring_easing, int = true }
end

-- Fade in/out for the width animation: blend the notification's highlight
-- groups toward the editor background (nvim-notify's `set_opacity` idea).
-- Two mechanisms are needed (verified with screen-attribute probes):
--  * winhl remaps for the window groups -- body, border glyphs, title/footer
--    and NormalFloat, which paints the float background/border ring. The
--    float's own background ignores a window highlight namespace; only a
--    winhl remap reaches it;
--  * a window-local highlight namespace for the style's extmark groups (the
--    fancy style draws icon/title/separator with extmarks, which winhl cannot
--    reach).
-- Private groups live in a small reusable slot pool so nothing accumulates.
local fade_pool, fade_next, fade_ns = {}, 0, {}
local function fade_slot()
    local slot = fade_next % 64 + 1
    for _ = 1, 64 do
        if not fade_pool[slot] then
            fade_pool[slot] = true
            fade_next = slot
            if not fade_ns[slot] then
                -- "fade2": namespaces cannot be deleted and an earlier
                -- implementation used "snacks_notif_fade_" with
                -- Normal/NormalFloat/... definitions; reusing that name would
                -- resurrect those stale definitions, which take precedence
                -- over winhl and break the notification's colors
                fade_ns[slot] = vim.api.nvim_create_namespace("snacks_notif_fade2_" .. slot)
            end
            return slot
        end
        slot = slot % 64 + 1
    end
    -- all 64 slots busy (unreachable in practice): skip the fade rather than
    -- alias a live slot, which would make two windows fight over one group
    return nil
end

---@param name string
---@return table? resolved attrs plus fg/bg as hex strings
local function fade_base(name)
    -- follow links manually from the raw definitions: nvim_get_hl's link
    -- resolution can be influenced by the current window's winhighlight
    local h = vim.api.nvim_get_hl(0, { name = name })
    local seen = {}
    while h and h.link and not seen[h.link] do
        seen[h.link] = true
        h = vim.api.nvim_get_hl(0, { name = h.link })
    end
    if not h then
        return nil
    end
    local attrs = {}
    for k, v in pairs(h) do
        if k ~= "default" and k ~= "link" then
            attrs[k] = v
        end
    end
    local fg = attrs.fg and string.format("#%06x", attrs.fg)
    local bg = attrs.bg and string.format("#%06x", attrs.bg)
    -- body groups link to NormalFloat/Normal which may have no fg (transparent
    -- themes): fall back to the global Normal fg so the text still fades
    if not fg and name:match("^SnacksNotifier%w*$") then
        fg = Snacks.util.color("Normal", "fg")
    end
    if not fg and not bg then
        return nil
    end
    return { attrs = attrs, fg = fg, bg = bg }
end

local function fade_blend(g, target, alpha)
    local hl = {}
    for k, v in pairs(g.attrs) do
        hl[k] = v
    end
    if g.fg then
        hl.fg = Snacks.util.blend(g.fg, target, alpha)
    end
    if g.bg then
        hl.bg = Snacks.util.blend(g.bg, target, alpha)
    end
    return hl
end

local function notif_fade_setup(win)
    if win._notif_fade then
        return win._notif_fade
    end
    local winhl = vim.wo[win.win].winhighlight
    if not winhl or winhl == "" then
        return nil
    end
    local target = Snacks.util.color("Normal", "bg")
        or Snacks.util.color("NormalFloat", "bg")
        or (vim.o.background == "light" and "#ffffff" or "#000000")
    local slot = fade_slot()
    if not slot then
        return nil
    end
    local fade = { slot = slot, target = target, winhl = winhl, groups = {}, ns_groups = {} }
    local remap = {}
    for from, to in winhl:gmatch("([%w_]+):([%w_]+)") do
        local base = fade_base(to)
        if base then
            local name = string.format("SnacksNotifFade%s%d", from, slot)
            fade.groups[#fade.groups + 1] = { name = name, attrs = base.attrs, fg = base.fg, bg = base.bg }
            remap[from] = name
        end
    end
    -- the float's own background (the border ring) is painted from NormalFloat
    local nf = fade_base("NormalFloat")
    if nf then
        local name = string.format("SnacksNotifFadeNormalFloat%d", slot)
        fade.groups[#fade.groups + 1] = { name = name, attrs = nf.attrs, fg = nf.fg, bg = nf.bg }
        remap.NormalFloat = name
    end
    -- extmark groups of the current style, applied through the namespace
    local suffix = winhl:match("Normal:SnacksNotifier(%w*)") or winhl:match("NormalNC:SnacksNotifier(%w*)")
    if suffix then
        for _, key in ipairs({ "Icon", "Title", "Border", "Footer" }) do
            local src = "SnacksNotifier" .. key .. suffix
            local base = fade_base(src)
            if base then
                fade.ns_groups[#fade.ns_groups + 1] = { name = src, attrs = base.attrs, fg = base.fg, bg = base.bg }
            end
        end
    end
    if #fade.groups == 0 and #fade.ns_groups == 0 then
        fade_pool[slot] = nil
        return nil
    end
    local parts = {}
    for from, to in winhl:gmatch("([%w_]+):([%w_]+)") do
        parts[#parts + 1] = from .. ":" .. (remap[from] or to)
    end
    if remap.NormalFloat then
        parts[#parts + 1] = "NormalFloat:" .. remap.NormalFloat
    end
    fade.faded_winhl = table.concat(parts, ",")
    if #fade.ns_groups > 0 then
        -- attach the namespace first: nvim_win_set_hl_ns resets the winhl
        -- effectiveness, so the winhl must be (re-)set after it
        vim.api.nvim_win_set_hl_ns(win.win, fade_ns[slot])
    end
    vim.wo[win.win].winhighlight = fade.faded_winhl
    win._notif_fade = fade
    return fade
end

-- alpha 0 = blended into the editor background, 1 = the original colors
local function notif_fade_apply(win, alpha)
    local fade = win._notif_fade or notif_fade_setup(win)
    if not fade or not win:win_valid() then
        return
    end
    alpha = math.min(1, math.max(0, alpha))
    for _, g in ipairs(fade.groups) do
        vim.api.nvim_set_hl(0, g.name, fade_blend(g, fade.target, alpha))
    end
    for _, g in ipairs(fade.ns_groups) do
        vim.api.nvim_set_hl(fade_ns[fade.slot], g.name, fade_blend(g, fade.target, alpha))
    end
    -- the notifier's update() re-applies the original winhl: re-assert
    vim.wo[win.win].winhighlight = fade.faded_winhl
end

local function notif_fade_clear(win)
    local fade = win._notif_fade
    if not fade then
        return
    end
    win._notif_fade = nil
    if win:win_valid() then
        -- order matters: detaching the namespace resets the winhl effectiveness,
        -- so the winhl must be re-asserted AFTER it or the window falls back to
        -- the global Normal (verified with screen-attr probes)
        vim.api.nvim_win_set_hl_ns(win.win, 0)
        -- the notifier's update() may have installed a newer winhl (same-id
        -- replace with another level/hl) while the fade was running: prefer
        -- the live intended value over the one captured at setup
        vim.wo[win.win].winhighlight = win.opts.wo.winhighlight or fade.winhl
    end
    for _, g in ipairs(fade.groups) do
        vim.api.nvim_set_hl(0, g.name, {})
    end
    fade_pool[fade.slot] = nil
end

-- Notification entrance/exit: unfold from / fold back into the right edge (see
-- the `styles.notification` hook). A true off-screen slide is impossible: nvim
-- clamps floats to stay fully on-screen (verified: a float at col=vim.o.columns
-- renders pinned to the right edge), so it would pop in and only creep the last
-- column. Instead keep the window's right edge fixed and animate the width from
-- a sliver to full: the left edge sweeps left and the text slides in with it
-- (same trick as nvim-notify's slide stage). The exit is the reverse: shrink to
-- a sliver, then really close (N:hide calls win:close(); an instance-level
-- override animates before the close lands).
--
-- Driven by Snacks.animate (the engine snacks uses elsewhere: repeating uv
-- timer at the platform-appropriate fps -- see notif_anim_opts -- with integer
-- stepping), so the cadence matches the rest of the UI. The easing is the
-- closed form of nvim-notify's critically-damped spring (spring_easing above).
--
-- The target is re-read live from win:win_opts(): the notifier re-lays-out on
-- VimResized / same-id replace, and a target captured at entry would be
-- written back stale (the notifier's own layout bookkeeping then
-- short-circuits), leaving the window at old geometry -- possibly fully
-- off-screen. Re-layouts surface through the `update` wrapper, which restarts
-- the animation from the current width toward the new target (reusing the
-- animation id makes Snacks.animate stop the previous run automatically).
--
-- The width and the fade share one eased progress: alpha is derived from the
-- current width (2 cells = blended into the editor background, full = opaque),
-- so the unfold and the fade-in/out are a single motion (enter: unfold + fade
-- in; exit: shrink + fade out).
local function notifier_animate_in(win)
    if not win:win_valid() then
        return
    end

    -- on_win fires again when a notifier window hidden for lack of space is
    -- re-shown; without this reset the stale flag would skip its animations
    win._notif_closing = nil

    -- The notifier sets its winhl before the window is visible and nvim never
    -- applies it in that case: the body silently keeps the global Normal (this
    -- is why the picker-style float background never showed on notifications;
    -- verified with screen-attr probes -- an identical re-set while visible
    -- takes effect). Re-setting it after the window is shown makes it stick.
    local winhl = vim.wo[win.win].winhighlight
    if winhl ~= "" then
        vim.schedule(function()
            if win:win_valid() and vim.wo[win.win].winhighlight == winhl then
                vim.wo[win.win].winhighlight = winhl
            end
        end)
    end

    local anim_id = "snacks_notifier:" .. win.win
    win._notif_anim_id = anim_id

    if not win._notif_hooks_installed then
        win._notif_hooks_installed = true

        local orig_close = win.close
        win.close = function(self, ...)
            local args = { ... }
            if self._notif_closing or not self:win_valid() or not Snacks.animate.enabled({ buf = self.buf }) then
                return orig_close(self, ...)
            end
            local c = vim.api.nvim_win_get_config(self.win)
            if c.relative ~= "editor" or type(c.width) ~= "number" or c.width <= 3 then
                return orig_close(self, ...)
            end
            self._notif_closing = true
            local right = c.col + c.width -- inner right edge stays put
            local wrap = vim.wo[self.win].wrap
            local function apply(w)
                if not self:win_valid() then
                    return
                end
                vim.wo[self.win].wrap = false
                -- the width is the eased progress: fade out while shrinking
                notif_fade_apply(self, (w - 2) / math.max(1, c.width - 2))
                local cur = vim.api.nvim_win_get_config(self.win)
                pcall(vim.api.nvim_win_set_config, self.win, {
                    relative = cur.relative,
                    row = cur.row,
                    col = right - w,
                    width = w,
                })
                if vim.api.nvim__redraw then
                    pcall(vim.api.nvim__redraw, { win = self.win, valid = false, flush = true })
                end
            end
            self._notif_anim_w = c.width
            -- any update() during the exit re-applies the current frame
            self._notif_anim_restart = function()
                apply(self._notif_anim_w)
            end
            Snacks.animate(c.width, 2, function(w, ctx)
                if not self:win_valid() then
                    Snacks.animate.del(self._notif_anim_id)
                    notif_fade_clear(self)
                    return
                end
                self._notif_anim_w = w
                apply(w)
                if ctx.done then
                    Snacks.animate.del(self._notif_anim_id)
                    self._notif_anim_restart = nil
                    if self:win_valid() then
                        vim.wo[self.win].wrap = wrap
                    end
                    notif_fade_clear(self)
                    orig_close(self, unpack(args))
                end
            end, notif_anim_opts(self._notif_anim_id))
        end

        -- the notifier's update() (VimResized / same-id replace) applies the
        -- full geometry: re-apply the current frame so it can't flash, and
        -- restart toward the new target when it moved
        local orig_update = win.update
        win.update = function(self, ...)
            local ret = orig_update(self, ...)
            local fn = self._notif_anim_restart
            if fn then
                fn()
            end
            return ret
        end
    end

    if not Snacks.animate.enabled({ buf = win.buf }) then
        return
    end
    local cfg = vim.api.nvim_win_get_config(win.win)
    if cfg.relative ~= "editor" or type(cfg.width) ~= "number" or cfg.width <= 2 then
        return
    end

    -- the style wraps long messages; keep the display stable while the width
    -- changes (text slides instead of re-wrapping every frame)
    local wrap = vim.wo[win.win].wrap

    local function target()
        local ok, o = pcall(win.win_opts, win)
        if not ok or type(o.col) ~= "number" or type(o.width) ~= "number" then
            return nil
        end
        return o.col, o.width
    end
    local function apply(w)
        if not win:win_valid() or win._notif_closing then
            return
        end
        local col, tw = target()
        if not col then
            return
        end
        -- re-assert wrap: the notifier's update() (re-layout) may reset it
        vim.wo[win.win].wrap = false
        -- the width is the eased progress: fade in while unfolding
        notif_fade_apply(win, (w - 2) / math.max(1, tw - 2))
        -- keep the current row: the notifier may re-stack other notifs
        local cur = vim.api.nvim_win_get_config(win.win)
        pcall(vim.api.nvim_win_set_config, win.win, {
            relative = cur.relative,
            row = cur.row,
            col = col + tw - w,
            width = w,
        })
        -- flush per frame (nvim-notify does the same) so every step actually
        -- paints instead of being coalesced by the event loop
        if vim.api.nvim__redraw then
            pcall(vim.api.nvim__redraw, { win = win.win, valid = false, flush = true })
        end
    end

    local function finish()
        win._notif_anim_restart = nil
        if win:win_valid() then
            -- let the notifier land its exact geometry (corrects a re-layout
            -- that happened mid-animation) and restore wrap
            pcall(win.update, win)
            vim.wo[win.win].wrap = wrap
            notif_fade_clear(win)
        end
    end
    local function start(w0)
        local _, tw = target()
        if not tw then
            return
        end
        win._notif_anim_w = w0
        win._notif_anim_to = tw
        apply(w0)
        Snacks.animate(w0, tw, function(w, ctx)
            if not win:win_valid() then
                Snacks.animate.del(win._notif_anim_id)
                notif_fade_clear(win)
                return
            end
            if win._notif_closing then
                -- the exit animation owns the id now; drop this frame
                return
            end
            win._notif_anim_w = w
            apply(w)
            if ctx.done then
                Snacks.animate.del(win._notif_anim_id)
                finish()
            end
        end, notif_anim_opts(anim_id))
    end

    win._notif_anim_restart = function()
        if not win:win_valid() or win._notif_closing then
            return
        end
        local _, tw = target()
        if not tw then
            return
        end
        if tw == win._notif_anim_to then
            apply(win._notif_anim_w or 2)
        else
            start(win._notif_anim_w or 2)
        end
    end

    start(2)
end

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
                notification         = {
                    border = "solid",
                    wo = { wrap = true, winblend = 0 },
                    on_win = notifier_animate_in,
                },
                notification_history = {
                    border = "none",
                    wo = { winbar = "%=%#SnacksNotifierHistoryTitle# Notification History %=" },
                },
                input                = { row = 0.5 },
            },
        },
        config = function(_, opts)
            require("snacks").setup(opts)
            -- notifier body: float background instead of the editor bg (snacks
            -- defaults SnacksNotifier<Level> to a Normal link)
            local function fix_notifier_hl()
                for _, level in ipairs({ "Trace", "Debug", "Info", "Warn", "Error" }) do
                    vim.api.nvim_set_hl(0, "SnacksNotifier" .. level, { link = "NormalFloat" })
                end
            end
            fix_notifier_hl()
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
            vim.api.nvim_create_autocmd("ColorScheme", {
                callback = function()
                    vim.schedule(function()
                        fix_picker_hl()
                        fix_notifier_hl()
                    end)
                end,
            })
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
