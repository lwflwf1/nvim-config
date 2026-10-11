-- Slide effect: the unfold. A true off-screen slide is impossible (nvim clamps
-- floats to stay fully on-screen), so the window keeps its right edge and the
-- width sweeps from `target - sweep` to the target -- the left edge sweeps left
-- and the text slides in with it (the same trick as nvim-notify's slide stage,
-- anchor=NE + col=columns).
--
-- `sweep` (enter) and `sweep_out` (exit) are separate on purpose: the enter
-- wants a short sweep (fewer cells per frame = smoother), while the exit wants
-- the full shrink -- with a short sweep the window is still wide through the
-- low-alpha tail, which exposes the fade's perceptual order (the thin border
-- loses contrast before the glyphs at equal alpha); the fast full shrink hides
-- it behind the motion.
local M = {}

-- the notifier re-lays-out asynchronously (VimResized / same-id replace), so
-- the target is re-read live instead of captured at entry
local function target(win)
    local ok, o = pcall(win.win_opts, win)
    if not ok or type(o.col) ~= "number" or type(o.width) ~= "number" then
        return nil
    end
    return o.col, o.width
end

---@param opts { frequency: number, damping?: number, settle: number, sweep: number, sweep_out?: number, min?: number }
function M.new(opts)
    local sp = require("box.anim.spring").new(opts)
    local min = opts.min or 2
    return {
        id = "slide",
        duration = sp.duration,
        easing = sp.easing,
        target = target,
        ---@param dir "in"|"out"
        ---@param base? number restart: the current animated width
        setup = function(win, dir, base)
            local _, tw = target(win)
            if not tw then
                return nil
            end
            local sweep = dir == "in" and opts.sweep or (opts.sweep_out or math.huge)
            base = base or math.max(min, tw - sweep)
            -- prefer the window's intended wrap (win.opts.wo.wrap): the live
            -- value is `false` if a previous run was interrupted mid-flight
            local wrap = vim.wo[win.win].wrap
            if win.opts.wo and win.opts.wo.wrap ~= nil then
                wrap = win.opts.wo.wrap
            end
            return { base = base, to = tw, last_w = base, wrap = wrap }
        end,
        apply = function(win, es, p)
            local col, tw = target(win)
            if not col then
                return
            end
            local w = math.floor(es.base + (tw - es.base) * p + 0.5)
            es.last_w = w
            -- re-assert wrap: the notifier's update() (re-layout) may reset it
            vim.wo[win.win].wrap = false
            -- keep the current row: the notifier may re-stack other notifs
            local cur = vim.api.nvim_win_get_config(win.win)
            pcall(vim.api.nvim_win_set_config, win.win, {
                relative = cur.relative,
                row = cur.row,
                col = col + tw - w,
                width = w,
            })
            -- flush per frame (nvim-notify does the same) so every step
            -- actually paints instead of being coalesced by the event loop
            if vim.api.nvim__redraw then
                pcall(vim.api.nvim__redraw, { win = win.win, valid = false, flush = true })
            end
        end,
        clear = function(win, es)
            if win:win_valid() then
                vim.wo[win.win].wrap = es.wrap
            end
        end,
    }
end

return M
