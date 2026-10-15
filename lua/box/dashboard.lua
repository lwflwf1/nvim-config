-- Dashboard item patches.
--
-- There is nothing to add for sessions: snacks' default `preset.keys` already
-- ships the row (`dashboard.lua:99` ->
-- `{ key = "s", desc = "Restore Session", section = "session" }`), so the only
-- job is redirecting it. Its resolver `Snacks.dashboard.sections.session`
-- returns `mini.sessions.read()` with no argument, which prefers the *cwd's*
-- `Session.vim` and only falls back to the newest global session
-- (`mini/sessions.lua:164-170`) -- a restore, not a choice. That made `s`
-- behave like `<leader>pr` while `<leader>pc` was the only route to a picker.
--
-- Replacing the resolver rather than the row is what keeps this one function:
-- `preset.keys` and `sections` are lists, and snacks merges its config with
-- `Snacks.config.merge`, which treats a list as a scalar (`is_dict_like` is
-- false for a list, `init.lua:60-62`) and replaces it whole -- so supplying a
-- single entry would drop the other seven rows, and patching "the 6th row"
-- would silently break on any upstream reorder.
--
-- Given up: upstream probes seven session plugins here (persistence.nvim,
-- persisted.nvim, neovim-session-manager, possession.nvim, mini.sessions,
-- auto-session). Only mini.sessions is installed, so the probe always resolved
-- to mini.sessions anyway. The one other caller is `M.sections.projects`'
-- `opts.session` branch (`dashboard.lua:917`); this config has no `projects`
-- section, and that branch reads `session.action`, which we still provide.
local M = {}

function M.setup()
    require("snacks.dashboard").sections.session = function(item)
        return setmetatable({
            action = function()
                require("box.sessions").pick_read()
            end,
            desc = "Pick Session",          -- was upstream's "Restore Session"
            section = false, -- final: stop the resolver chain (dashboard.lua:481)
        }, { __index = item })
    end
end

return M