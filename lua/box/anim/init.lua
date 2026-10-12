-- Window animations, built on box/anim/core.lua (effects: box/anim/slide.lua,
-- box/anim/fade.lua; springs: box/anim/spring.lua).
--
-- Two ways in:
--   * attach(opts) -- for snacks.nvim windows. Wire it into a window style:
--       styles.<name>.on_win = require("box.anim").attach(<CONFIG>)
--     It installs the enter animation plus the exit/update interception on the
--     snacks Win object (win.close / win.update), so the close animates before
--     it lands.
--   * new(opts) -- the runner for any window (see box/anim/core.lua), e.g.
--       local anim = require("box.anim").new({ fade = {...} })
--       anim:enter(winid)
--       anim:exit(winid, function() vim.api.nvim_win_close(winid, false) end)
--     Nothing here is notifier-specific: box/anim/core.lua owns the mechanics.
local M = {}

M.new = require("box.anim.core").new

--- Snacks adapter. `opts` is the core config; the geometry comes from the
--- snacks Win object (its `win_opts` is the layout the notifier *intends*, which
--- survives a re-layout better than the live config), and the enabled gate
--- honours snacks' own `animate` setting.
---@param opts table
---@return fun(win: table) on_win hook for snacks window styles
function M.attach(opts)
    local runner = M.new(opts)

    --- the notifier re-lays-out asynchronously (VimResized / same-id replace), so
    --- the target is re-read live instead of captured at entry
    local function target(win)
        return function()
            local ok, o = pcall(win.win_opts, win)
            if not ok or type(o.col) ~= "number" or type(o.width) ~= "number" then
                return nil
            end
            return o.col, o.width, o.row, o.height
        end
    end

    return function(win)
        if not win:win_valid() then
            return
        end

        -- on_win fires again when a window hidden for lack of space is
        -- re-shown; without this reset the stale flag would skip its animations
        win._anim_closing = nil

        -- The notifier sets its winhl before the window is visible and nvim
        -- never applies it in that case: the body silently keeps the global
        -- Normal (this is why the float background never showed; verified with
        -- screen-attr probes -- an identical re-set while visible takes effect).
        -- Re-setting it after the window is shown makes it stick.
        local winhl = vim.wo[win.win].winhighlight
        if winhl ~= "" then
            vim.schedule(function()
                if win:win_valid() and vim.wo[win.win].winhighlight == winhl then
                    vim.wo[win.win].winhighlight = winhl
                end
            end)
        end

        if not win._anim_hooks_installed then
            win._anim_hooks_installed = true

            local orig_close = win.close
            win.close = function(self, ...)
                local args = { ... }
                if
                    self._anim_closing
                    or not self:win_valid()
                    or not Snacks.animate.enabled({ buf = self.buf })
                then
                    return orig_close(self, ...)
                end
                local c = vim.api.nvim_win_get_config(self.win)
                if c.relative ~= "editor" or type(c.width) ~= "number" or c.width <= 3 then
                    return orig_close(self, ...)
                end
                self._anim_closing = true
                runner:exit(self.win, function()
                    orig_close(self, unpack(args))
                end, {
                    target = target(self),
                    wrap = self.opts.wo and self.opts.wo.wrap,
                })
            end

            local orig_update = win.update
            win.update = function(self, ...)
                local ret = orig_update(self, ...)
                runner:resume(self.win)
                return ret
            end
        end

        if not Snacks.animate.enabled({ buf = win.buf }) then
            return
        end
        runner:enter(win.win, {
            target = target(win),
            wrap = win.opts.wo and win.opts.wo.wrap,
            -- let the notifier land its exact geometry once the enter finishes
            resume_host = function()
                pcall(win.update, win)
            end,
        })
    end
end

return M
