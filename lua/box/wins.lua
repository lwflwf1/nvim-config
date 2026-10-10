-- Directional window move/resize. Self-contained replacement for
-- smart-splits.nvim (mux integration no longer needed).
--
-- Movement reuses smart-splits' trick: `winnr("<count><dir>")` reaches the
-- Nth window in that direction and 99999 steps stops at the far edge, which
-- gives wrap-around for free.
--
-- Resize keeps smart-splits' "the boundary moves in the pressed direction"
-- semantics: plain arrows act on the trailing (right/bottom) boundary,
-- Shift+arrows on the leading (left/top) one. When a boundary sits at the
-- screen edge, fall back to resizing the only movable boundary (plugin
-- behavior). Amount = count * 3.
local M = {}

local DIR_KEYS = { left = "h", right = "l", up = "k", down = "j" }
local REV_KEYS = { left = "l", right = "h", up = "j", down = "k" }
local AMOUNT = 3

function M.move(dir)
    -- smart-splits guards cmdwin: set_current_win inside it can corrupt state
    if vim.fn.getcmdwintype() ~= "" then
        return
    end
    local count = vim.v.count1
    local key = DIR_KEYS[dir]
    -- Would we hit the edge before moving `count` windows?
    local to = vim.fn.winnr(count .. key)
    local before = count == 1 and vim.fn.winnr() or vim.fn.winnr((count - 1) .. key)
    local will_wrap = to == before
    if will_wrap and count == 1 then
        key = REV_KEYS[dir]
    end
    vim.api.nvim_set_current_win(vim.fn.win_getid(vim.fn.winnr((will_wrap and "99999" or count) .. key)))
end

--- Move the window boundary in `dir`.
--- @param dir "left"|"right"|"up"|"down" direction the boundary moves
--- @param leading? boolean Shift variant: act on the left/top boundary
function M.resize(dir, leading)
    local amount = vim.v.count1 * AMOUNT
    local horizontal = dir == "left" or dir == "right"
    local size_cmd = horizontal and "vertical resize " or "resize "
    local toward_positive = dir == "right" or dir == "down" -- boundary moves right/down
    local leading_key = horizontal and "h" or "k"
    local trailing_key = horizontal and "l" or "j"
    local at_leading = vim.fn.winnr() == vim.fn.winnr(leading_key)
    local at_trailing = vim.fn.winnr() == vim.fn.winnr(trailing_key)

    if leading and not at_leading then
        -- Move the leading boundary: grow the leading neighbour when the
        -- boundary moves towards us, shrink it otherwise. The neighbour
        -- takes/gives space from/to its trailing neighbour, which is us.
        local cur = vim.api.nvim_get_current_win()
        vim.cmd("wincmd " .. leading_key)
        vim.cmd(size_cmd .. (toward_positive and "+" or "-") .. amount)
        vim.api.nvim_set_current_win(cur)
        return
    end

    -- Trailing boundary, or smart fallback when the leading boundary is at
    -- the screen edge. Mirrors smart-splits' position logic: start/middle
    -- grows towards right/down; the last window (at the trailing edge only)
    -- inverts.
    local bigger
    if leading then
        bigger = toward_positive -- fallback: leading edge behaves like "start"
    else
        local last = at_trailing and not at_leading
        bigger = toward_positive ~= last
    end
    vim.cmd(size_cmd .. (bigger and "+" or "-") .. amount)
end

function M.setup()
    local map = function(modes, lhs, rhs, desc)
        vim.keymap.set(modes, lhs, rhs, { noremap = true, silent = true, desc = desc })
    end
    -- Movement works in insert/terminal too; plain arrows move the right/bottom
    -- boundary, Shift+arrows the left/top one.
    map({ "n", "i", "t" }, "<M-h>", function() M.move("left") end, "Move to split left")
    map({ "n", "i", "t" }, "<M-j>", function() M.move("down") end, "Move to split down")
    map({ "n", "i", "t" }, "<M-k>", function() M.move("up") end, "Move to split up")
    map({ "n", "i", "t" }, "<M-l>", function() M.move("right") end, "Move to split right")
    map("n", "<Left>", function() M.resize("left") end, "Resize right boundary left")
    map("n", "<Right>", function() M.resize("right") end, "Resize right boundary right")
    map("n", "<Up>", function() M.resize("up") end, "Resize bottom boundary up")
    map("n", "<Down>", function() M.resize("down") end, "Resize bottom boundary down")
    map("n", "<S-Left>", function() M.resize("left", true) end, "Resize left boundary left")
    map("n", "<S-Right>", function() M.resize("right", true) end, "Resize left boundary right")
    map("n", "<S-Up>", function() M.resize("up", true) end, "Resize top boundary up")
    map("n", "<S-Down>", function() M.resize("down", true) end, "Resize top boundary down")
end

return M
