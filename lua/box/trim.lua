-- Trailing whitespace / CR trim (<leader>ue). Also used by the lualine
-- fileformat click (plugins/ui.lua), which is why trim_trailing is exported.
local M = {}

-- strip CRs first -- mini's \s\+$ does not match \r, so "word \r" would
-- otherwise keep both the space and the CR. winsaveview: :s jumps to the last
-- changed line.
function M.trim_trailing()
    if not vim.bo.modifiable then
        return
    end
    local view = vim.fn.winsaveview()
    vim.cmd([[silent keepjumps keeppatterns %s/\r\+$//e]])
    vim.fn.winrestview(view)
    require("mini.trailspace").trim()
end

function M.setup()
    vim.keymap.set("n", "<leader>ue", M.trim_trailing,
        { noremap = true, silent = true, desc = "Trim trailing whitespace and ^M" })
end

return M
