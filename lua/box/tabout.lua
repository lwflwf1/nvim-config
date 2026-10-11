-- Rule engine for the smart multistep keys wired in plugins/editing.lua:
--
--   <Tab>:   minuet ghost text accept > blink menu next > tab-out > raw Tab
--   <S-Tab>: blink menu prev > step back in over a closer > dedent
--   <CR>:    blink accept (selected item only) > mini.pairs expansion > raw CR
--
-- This module exports only the tab-out step functions (M.condition /
-- M.action / M.back_in_condition). The chains themselves are declared where
-- mini.keymap is set up (plugins/editing.lua), and this module imports
-- nothing -- no mini, no blink, no minuet.
--
-- M.action replicates the albert.TabOut rules (as reverse-documented in
-- zed#22349):
--   1) all-whitespace left of cursor = indent zone -> rule fails -> raw Tab
--   3) cursor immediately before a closer/quote  -> skip one char
--   4) cursor immediately before an opener -> skip one char
--   5) cursor immediately after an opener -> jump past the MATCHING closer on
--      that line (nest-aware; quotes pair lazily); no matching closer ->
--      rule fails (chosen over TabOut's ambiguous "one more step", which
--      reads as a dead key at EOL in nvim)
-- Deliberately NOT replicated: TabOut's odd same-char skips for `: ; = > < .`,
-- multi-line spans, and its escaped-quote counting bug.
-- mini.keymap's builtin jump_after_close lacks rules 1/4/5, hence this engine.

local M = {}

local jumpable_list = { ')', ']', '}', '(', '[', '{', '"', "'", '`' }
local pair = { ['('] = ')', ['['] = ']', ['{'] = '}' }
local same = { '"', "'", '`' }

-- cursor col is 0-based: char BEFORE cursor = 1-based col, right = col+1
local function line_ctx()
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    local line = vim.api.nvim_buf_get_lines(0, row - 1, row, true)[1] or ''
    local left, right = line:sub(col, col), line:sub(col + 1, col + 1)
    return line, col, left, right, row
end

-- TabOut rule 1: left of the cursor is all whitespace = indent zone
local function mid_line(line, col)
    return line:sub(1, col):find('%g') ~= nil
end

local function jumpable(char)
    return char ~= '' and vim.list_contains(jumpable_list, char)
end

-- returns an action that lands the cursor 0-based at col_1based (i.e. after
-- the closer sitting at 1-based column col_1based)
local function jump_to(row, col_1based)
    return function()
        vim.api.nvim_win_set_cursor(0, { row, col_1based })
    end
end

--- Tab-out step condition: mid-line AND a jumpable char adjacent (either side)
M.condition = function()
    local line, col, left, right = line_ctx()
    return mid_line(line, col) and (jumpable(left) or jumpable(right))
end

--- Tab-out step action (see the rule list in the header)
M.action = function()
    local line, col, left, right, row = line_ctx()
    -- rule 5: cursor after an opener -> jump past its matching closer
    local closer = pair[left]
    if closer then
        local depth = 1
        for i = col + 1, #line do
            local c = line:sub(i, i)
            if c == left then
                depth = depth + 1
            elseif c == closer then
                depth = depth - 1
                if depth == 0 then
                    return jump_to(row, i)
                end
            end
        end
        return false -- unclosed: raw Tab (per user choice, see header)
    end
    if vim.list_contains(same, left) then
        local j = line:find(left, col + 1, true)
        if j then
            return jump_to(row, j)
        end
        return false
    end
    -- rules 3+4: skip a single adjacent closer or opener
    return vim.list_contains(jumpable_list, right) and "<Right>" or false
end

--- <S-Tab> step condition: mid-line AND the left neighbor is jumpable
--- (step back in over a closer)
M.back_in_condition = function()
    local line, col, left = line_ctx()
    return mid_line(line, col) and jumpable(left)
end

return M
