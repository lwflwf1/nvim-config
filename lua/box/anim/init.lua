-- Core for the notifier enter/exit animation: runs the configured effects
-- (box/anim/slide, box/anim/fade) as independent Snacks.animate runs, each
-- with its own spring and duration, so effects can be enabled, disabled or
-- re-timed separately. Exit interception is installed on the snacks Win
-- object (win.close / win.update), so this currently only drives notifier
-- windows; other windows can reuse it later by passing their own config.
--
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

local M = {}

---@class anim.Effect
---@field id string
---@field duration number ms, derived from the spring
---@field easing fun(t: number, b: number, c: number, d: number): number
---@field setup fun(win: table, dir: "in"|"out", base?: number): table?
---@field apply fun(win: table, es: table, p: number)
---@field clear fun(win: table, es: table)

---@param opts { fps?: number, slide?: table|false, fade?: table|false }
---@return fun(win: table) on_win hook for snacks windows
function M.attach(opts)
    local fps = opts.fps or 120
    ---@type anim.Effect[]
    local effects = {}
    local slide_idx
    if opts.slide and opts.slide.enable ~= false then
        slide_idx = #effects + 1
        effects[slide_idx] = require("box.anim.slide").new(opts.slide)
    end
    if opts.fade and opts.fade.enable ~= false then
        effects[#effects + 1] = require("box.anim.fade").new(opts.fade)
    end

    if #effects == 0 then
        return function() end
    end

    local check_done

    local function finish(win, st)
        win._notif_anim = nil
        if not win:win_valid() then
            for i, eff in ipairs(effects) do
                eff.clear(win, st.states[i])
            end
            return
        end
        if st.dir == "in" then
            -- let the notifier land its exact geometry (corrects a re-layout
            -- that happened mid-animation), then restore wrap/winhl
            pcall(win.update, win)
            for i, eff in ipairs(effects) do
                eff.clear(win, st.states[i])
            end
        else
            for i, eff in ipairs(effects) do
                eff.clear(win, st.states[i])
            end
            st.orig_close(win, unpack(st.args))
        end
    end

    check_done = function(win, st)
        for i = 1, #effects do
            if not st.done[i] then
                return
            end
        end
        finish(win, st)
    end

    local function run_effect(win, st, i, dir)
        local eff = effects[i]
        local es = st.states[i]
        local id = st.id .. ":" .. eff.id
        local from, to = dir == "in" and 0 or 100, dir == "in" and 100 or 0
        Snacks.animate(from, to, function(v, ctx)
            if win._notif_anim ~= st then
                -- superseded (the exit took over, or the run restarted)
                return
            end
            if not win:win_valid() then
                Snacks.animate.del(id)
                eff.clear(win, es)
                return
            end
            st.p[i] = v / 100
            eff.apply(win, es, st.p[i])
            if ctx.done then
                st.done[i] = true
                check_done(win, st)
            end
        end, { id = id, fps = fps, duration = { total = eff.duration }, easing = eff.easing, int = false })
    end

    local function start(win, dir, ctx)
        local st = {
            id = "snacks_notifier:" .. win.win,
            dir = dir,
            states = {},
            done = {},
            p = {},
            orig_close = ctx and ctx.orig_close,
            args = ctx and ctx.args,
        }
        win._notif_anim = st
        for i in ipairs(effects) do
            local es = effects[i].setup(win, dir)
            st.states[i] = es
            if es then
                -- land the initial frame immediately: otherwise the window
                -- shows at its resting geometry/opacity until the first timer
                -- tick (~8-16ms) and flashes
                if dir == "in" then
                    effects[i].apply(win, es, 0)
                end
                run_effect(win, st, i, dir)
            else
                st.done[i] = true
            end
        end
        check_done(win, st)
    end

    -- re-layout mid-enter: re-apply the current slide frame so it can't flash,
    -- and restart toward a moved target (the fade is time-based, not geometry,
    -- so it keeps running)
    local function resume(win, st)
        if st.dir ~= "in" or not slide_idx then
            return
        end
        local eff = effects[slide_idx]
        local es = st.states[slide_idx]
        if not es then
            return
        end
        local _, tw = eff.target(win)
        if not tw then
            return
        end
        if tw == es.to then
            eff.apply(win, es, st.p[slide_idx] or 0)
        else
            -- target moved: restart the slide run from the current width
            local nst = eff.setup(win, "in", es.last_w)
            if nst then
                st.states[slide_idx] = nst
                st.done[slide_idx] = false
                run_effect(win, st, slide_idx, "in")
            end
        end
    end

    return function(win)
        if not win:win_valid() then
            return
        end

        -- on_win fires again when a notifier window hidden for lack of space
        -- is re-shown; without this reset the stale flag would skip its
        -- animations
        win._notif_closing = nil

        -- The notifier sets its winhl before the window is visible and nvim
        -- never applies it in that case: the body silently keeps the global
        -- Normal (this is why the picker-style float background never showed
        -- on notifications; verified with screen-attr probes -- an identical
        -- re-set while visible takes effect). Re-setting it after the window
        -- is shown makes it stick.
        local winhl = vim.wo[win.win].winhighlight
        if winhl ~= "" then
            vim.schedule(function()
                if win:win_valid() and vim.wo[win.win].winhighlight == winhl then
                    vim.wo[win.win].winhighlight = winhl
                end
            end)
        end

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
                start(self, "out", { orig_close = orig_close, args = args })
            end

            local orig_update = win.update
            win.update = function(self, ...)
                local ret = orig_update(self, ...)
                local st = self._notif_anim
                if st then
                    resume(win, st)
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

        start(win, "in")
    end
end

return M
