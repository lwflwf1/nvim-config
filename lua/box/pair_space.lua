-- Space inside empty bracket pairs. Wired from plugins/editing.lua as
-- mini.keymap multistep steps. Imports nothing.
--
--   (|) + <Space> -> ( | )
--   ( | ) + <BS>  -> (|)

local M = {}

local pair = { ["("] = ")", ["["] = "]", ["{"] = "}" }

local function ctx()
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    local line = vim.api.nvim_buf_get_lines(0, row - 1, row, true)[1] or ""
    return line, col
end

function M.space_condition()
    local line, col = ctx()
    return pair[line:sub(col, col)] == line:sub(col + 1, col + 1)
end

function M.space_action()
    return "<Space><Space><Left>"
end

function M.bs_condition()
    local line, col = ctx()
    if col < 2 then return false end
    local l2, l1, r1, r2 =
        line:sub(col - 1, col - 1),
        line:sub(col, col),
        line:sub(col + 1, col + 1),
        line:sub(col + 2, col + 2)
    return l1 == " " and r1 == " " and pair[l2] == r2
end

function M.bs_action()
    return "<BS><Del>"
end

return M
