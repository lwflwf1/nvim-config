-- Generic window animation core.
--
-- Runs a set of independent effects (box/anim/slide, box/anim/fade, ...) on a
-- window, each as its own Snacks.animate pass with its own spring, so effects
-- can be enabled, disabled or re-timed separately. snacks is still the engine
-- (Snacks.animate schedules the frames, Snacks.util.blend mixes colours); what
-- the core does NOT depend on is the snacks *window model* -- the caller hands
-- it a plain window id plus an optional per-window descriptor, and it owns the
-- shared parts -- session bookkeeping (keyed by winid, so it works for windows
-- that have no Lua object, i.e. anything from nvim_open_win), the enter/exit
-- direction, landing the first frame immediately, letting the exit finish before
-- the window really closes, and cleaning up if a window dies underneath it.
--
-- Entry points:
--   * box/anim.init.attach(opts) -> a snacks.nvim `on_win` hook
--   * box/anim.init.new(opts)    -> a runner for any window
--       runner.enter(winid[, ctx])   start the enter animation
--       runner.exit(winid, finally)  animate out, then call finally()
--       runner.stop(winid)           drop the animation without animating out
--       runner.resume(winid)         re-assert after an external re-layout
--
-- Effect contract (box/anim/slide.lua, box/anim/fade.lua):
--   eff.id      string
--   eff.duration, eff.easing    from box/anim/spring
--   eff.setup(aw, dir, base?) -> es|nil     nil = this effect skips the window
--   eff.apply(aw, es, p)                    p is 0..1
--   eff.clear(aw, es)
-- `aw` (animation window) is the runtime descriptor the core builds per window:
--   aw.win    winid (number)
--   aw.buf    bufnr
--   aw.target() -> col, width, row, height   the window's intended geometry
--   aw.wrap   intended `wrap` value, or nil  (only when the host knows better
--             than the live option, e.g. after an interrupted run)
--   aw.valid() -> boolean
local M = {}

-- Windows' default timer resolution is ~15.6ms, which quantizes uv timers to
-- ~15.6ms (measured: an 8ms interval fires at ~15.6ms, and 16ms rounds up to
-- 31ms) and caps the animation at ~64fps. Requesting 1ms resolution via
-- winmm.timeBeginPeriod(1) lets the same timer fire at ~8.5ms, so the animation
-- can run at 120fps. The request is released automatically when the process
-- exits; LuaJIT's ffi is always available in nvim.
if vim.g.os == "windows" then
    pcall(function()
        local ffi = require("ffi")
        ffi.cdef("unsigned int timeBeginPeriod(unsigned int);")
        ffi.load("winmm").timeBeginPeriod(1)
    end)
end

--- sessions keyed by winid: a window's session outlives the Lua object that
--- started it (snacks creates a fresh Win per notification), and raw floats
--- never have one at all, so the winid is the only stable key
---@type table<number, table>
local sessions = {}

---@param winid number
local function make_aw(winid, ctx)
    -- When the host does not supply a target, snapshot the geometry once: a
    -- fake `get_config` read would follow the effect's own writes (the slide
    -- sets width/col every frame), so the target would chase the animation and
    -- it would collapse. A host that re-lays-out live (snacks) passes its own
    -- `target` instead.
    local snap
    if not (ctx and ctx.target) then
        local c = vim.api.nvim_win_get_config(winid)
        snap = { c.col, c.width, c.row, c.height }
    end
    return {
        win = winid,
        buf = vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_buf(winid) or nil,
        target = (ctx and ctx.target) or function()
            return snap[1], snap[2], snap[3], snap[4]
        end,
        wrap = ctx and ctx.wrap,
        valid = function()
            return vim.api.nvim_win_is_valid(winid)
        end,
    }
end

local cleanup_installed = false
---@param winid number
local function cleanup(winid)
    local st = sessions[winid]
    if not st then
        return
    end
    sessions[winid] = nil
    for i, eff in ipairs(st.runner.effects) do
        pcall(eff.clear, st.aw, st.states[i])
    end
end

--- a window can be destroyed by its host (a tab closing, :bwipeout, an LSP
--- shutdown ...) while an effect still holds a namespace slot or has patched
--- window options, so always release the session
local function install_cleanup()
    if cleanup_installed then
        return
    end
    cleanup_installed = true
    vim.api.nvim_create_autocmd("WinClosed", {
        callback = function(ev)
            cleanup(tonumber(ev.match))
        end,
    })
end

--- @class anim.Runner
--- @field opts table
--- @field effects anim.Effect[]

--- Build the effect set. `opts` is the caller's config:
---   fps     number (default 120)
---   id      string  animation id prefix (default "anim")
---   slide   table|false
---   fade    table|false
---   enabled fun(aw): boolean?  extra gate, e.g. snacks' own animate setting
--- @param opts table
--- @return anim.Runner
function M.new(opts)
    opts = opts or {}
    local fps = opts.fps or 120
    local id = opts.id or "anim"
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

    local runner = setmetatable({
        opts = opts,
        effects = effects,
        id = id,
        fps = fps,
        slide_idx = slide_idx,
    }, { __index = M })

    if #effects == 0 then
        return runner
    end
    install_cleanup()

    local function check_done(st)
        for i = 1, #effects do
            if not st.done[i] then
                return
            end
        end
        runner:_finish(st)
    end

    local function run_effect(st, i, dir)
        local eff = effects[i]
        local es = st.states[i]
        local aid = st.id .. ":" .. eff.id
        local from, to = dir == "in" and 0 or 100, dir == "in" and 100 or 0
        Snacks.animate(from, to, function(v, ctx)
            if sessions[st.win] ~= st then
                -- superseded (the exit took over, or the run restarted); the
                -- new run reuses the same animation id, so nothing leaks
                return
            end
            if not st.aw.valid() then
                Snacks.animate.del(aid)
                eff.clear(st.aw, es)
                return
            end
            st.p[i] = v / 100
            eff.apply(st.aw, es, st.p[i])
            if ctx.done then
                st.done[i] = true
                check_done(st)
            end
        end, { id = aid, fps = fps, duration = { total = eff.duration }, easing = eff.easing, int = false })
    end

    runner._run_effect = run_effect
    runner._check_done = check_done
    return runner
end

--- Start `dir` ("in" or "out"). ctx may carry per-window overrides:
---   target fun() -> col, width, row, height
---   wrap   intended `wrap` value
---   finally fun()  called after an "out" run finishes (the real close)
---@param winid number
---@param dir "in"|"out"
---@param ctx? table
function M:start(winid, dir, ctx)
    local aw = make_aw(winid, ctx)
    local st = {
        runner = self,
        win = winid,
        id = self.id .. ":" .. winid,
        dir = dir,
        aw = aw,
        states = {},
        done = {},
        p = {},
        finally = ctx and ctx.finally,
    }
    sessions[winid] = st
    for i in ipairs(self.effects) do
        local es = self.effects[i].setup(aw, dir)
        st.states[i] = es
        if es then
            -- land the initial frame immediately: otherwise the window shows at
            -- its resting geometry/opacity until the first timer tick (~8-16ms)
            -- and flashes
            if dir == "in" then
                self.effects[i].apply(aw, es, 0)
            end
            self._run_effect(st, i, dir)
        else
            st.done[i] = true
        end
    end
    self._check_done(st)
end

--- @param st table
function M:_finish(st)
    if sessions[st.win] ~= st then
        return
    end
    sessions[st.win] = nil
    if not st.aw.valid() then
        for i, eff in ipairs(self.effects) do
            pcall(eff.clear, st.aw, st.states[i])
        end
        return
    end
    if st.dir == "in" then
        -- let the host land its exact geometry (corrects a re-layout that
        -- happened mid-animation), then restore whatever the effects changed
        if st.resume_host then
            pcall(st.resume_host)
        end
        for i, eff in ipairs(self.effects) do
            eff.clear(st.aw, st.states[i])
        end
    else
        for i, eff in ipairs(self.effects) do
            eff.clear(st.aw, st.states[i])
        end
        if st.finally then
            st.finally()
        end
    end
end

--- The enter animation. Returns false if the window cannot be animated.
---@param winid number
---@param ctx? table
---@return boolean
function M:enter(winid, ctx)
    if not vim.api.nvim_win_is_valid(winid) then
        return false
    end
    local c = vim.api.nvim_win_get_config(winid)
    -- only floats have an animatable geometry (col/width/row/height); a leaf
    -- would need a resize effect instead
    if not c.relative or c.relative == "" or type(c.width) ~= "number" or c.width <= 2 then
        return false
    end
    if self.opts.enabled and not self.opts.enabled(make_aw(winid, ctx)) then
        return false
    end
    self:start(winid, "in", ctx)
    return true
end

--- Animate the window out, then run `finally` (e.g. the real close). Falls back
--- to calling `finally` immediately when there is nothing to animate.
---@param winid number
---@param finally fun()
---@param ctx? table
function M:exit(winid, finally, ctx)
    local st = sessions[winid]
    if not st or st.dir ~= "in" then
        -- no enter in flight: nothing to take over, but an enter could still be
        -- restarted by a late on_win -- so only bail out when the window is
        -- already gone
        if not vim.api.nvim_win_is_valid(winid) then
            return finally()
        end
    end
    if not vim.api.nvim_win_is_valid(winid) then
        return finally()
    end
    local c = vim.api.nvim_win_get_config(winid)
    if not c.relative or c.relative == "" or type(c.width) ~= "number" or c.width <= 3 then
        return finally()
    end
    if self.opts.enabled and not self.opts.enabled(make_aw(winid, ctx)) then
        return finally()
    end
    if st then
        ctx = ctx or {}
        ctx.target = ctx.target or st.aw.target
        ctx.wrap = ctx.wrap or st.aw.wrap
    end
    ctx = ctx or {}
    ctx.finally = finally
    self:start(winid, "out", ctx)
end

--- Drop the animation on `winid` and restore the window, without animating out.
---@param winid number
function M:stop(winid)
    local st = sessions[winid]
    if not st then
        return
    end
    sessions[winid] = nil
    for i, eff in ipairs(self.effects) do
        Snacks.animate.del(st.id .. ":" .. eff.id)
        pcall(eff.clear, st.aw, st.states[i])
    end
end

--- Re-assert the current frame after the host re-laid out the window: re-apply
--- so it cannot flash, and restart the slide toward a moved target (the fade is
--- time-based, not geometry-based, so it just keeps running).
---@param winid number
function M:resume(winid)
    local st = sessions[winid]
    if not st or st.dir ~= "in" or not self.slide_idx then
        return
    end
    local eff = self.effects[self.slide_idx]
    local es = st.states[self.slide_idx]
    if not es then
        return
    end
    local _, tw = st.aw.target()
    if not tw then
        return
    end
    if tw == es.to then
        eff.apply(st.aw, es, st.p[self.slide_idx] or 0)
    else
        -- target moved: restart the slide run from the current width
        local nst = eff.setup(st.aw, "in", es.last_w)
        if nst then
            st.states[self.slide_idx] = nst
            st.done[self.slide_idx] = false
            self._run_effect(st, self.slide_idx, "in")
        end
    end
end

return M
