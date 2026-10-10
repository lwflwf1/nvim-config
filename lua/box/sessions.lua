-- mini.sessions helpers shared by the editing.lua keymaps and the lualine
-- session component: current-session name/state plus the smart-save and
-- pick-to-read actions (single source of truth for both entry points).
local M = {}

---@return string current session name without extension, "" when none
function M.name()
    return vim.fn.fnamemodify(vim.v.this_session, ":t:r")
end

---@return boolean
function M.active()
    return vim.v.this_session ~= ""
end

---@return string|nil
function M.kind()
    if M.active() then
        return vim.fn.fnamemodify(vim.v.this_session, ":t") == require("mini.sessions").config.file and "local" or "global"
    end
    return nil
end

--- Save: write the active session back silently, or prompt for a name the
--- first time (the <leader>ps / left-click action).
function M.save()
    if M.active() then
        require("mini.sessions").write(nil)
    else
        vim.ui.input({ prompt = "Session name: " }, function(name)
            if name and name ~= "" then
                require("mini.sessions").write(name)
            end
        end)
    end
end

--- Pick a session to read (<leader>pc / right-click).
function M.pick_read()
    require("mini.sessions").select("read")
end

return M
