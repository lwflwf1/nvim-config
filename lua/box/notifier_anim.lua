-- Notifier enter/exit width animation (unfold/shrink + fade) for snacks.nvim,
-- driven by Snacks.animate with a critically-damped spring. Extracted from
-- plugins/snacks.lua, which aliases it as notifier_animate_in.
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

return { notifier_animate_in = notifier_animate_in }
