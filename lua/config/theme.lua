-- Single source of truth for the default theme (option A) + persistence of the
-- last choice (option B). Startup: state file > default; exit: VimLeavePre
-- writes the final colors_name back to the state file (picker preview switches
-- themes temporarily and restores on cancel, so the value at exit is the real
-- one -- no need to hook picker internals).
local M = {}

M.default = "onedark"
M.statefile = vim.fn.stdpath("state") .. "/colorscheme"

function M.set(name)
    pcall(vim.cmd.colorscheme, name)
    -- fall back to default when the saved theme no longer exists (e.g. plugin removed)
    if vim.g.colors_name == nil and name ~= M.default then
        pcall(vim.cmd.colorscheme, M.default)
    end
end

function M.setup()
    local f = io.open(M.statefile, "r")
    local saved
    if f then
        saved = f:read("*l")
        f:close()
    end
    if saved == nil or saved == "" then
        saved = M.default
    end
    M.set(saved)

    vim.api.nvim_create_autocmd("VimLeavePre", {
        group = vim.api.nvim_create_augroup("theme_state", { clear = true }),
        callback = function()
            local name = vim.g.colors_name
            if not name or name == "" then
                return
            end
            vim.fn.mkdir(vim.fn.fnamemodify(M.statefile, ":h"), "p")
            local out = io.open(M.statefile, "w")
            if out then
                out:write(name)
                out:close()
            end
        end,
    })
end

return M
