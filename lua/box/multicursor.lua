-- Neovim 0.13 built-in multicursor glue: the 1Q* feedkey sequences that add
-- cursors, the shared namespace, and the activity check (also used by
-- plugins/yanky.lua to fall back to the built-in put).
local M = {}

local nohl = vim.keycode("<Cmd>nohlsearch<CR>")
local ns = vim.api.nvim_create_namespace("nvim.multicursor")

---@return boolean true while the buffer has extra (1Q) cursors
function M.is_active()
    return #vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { limit = 1 }) > 0
end

local function clear()
    vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)
end

function M.setup()
    local function mc_feed(keys)
        return function()
            vim.api.nvim_feedkeys("2q="..keys:rep(vim.v.count1).."1q=", "nxi", false)
        end
    end

    local function mc_match(direction)
        return function()
            local seq = "1Q" .. direction
            seq = seq:rep(vim.v.count1) .. nohl
            if not M.is_active() then
                seq = '"_yiw' .. seq
            end
            vim.api.nvim_feedkeys("2q="..seq.."1q=", "nxi", false)
        end
    end

    local map = function(lhs, rhs, desc)
        vim.keymap.set("n", lhs, rhs, { noremap = true, silent = true, desc = desc })
    end
    map("<Esc>", function()
        if M.is_active() then
            clear()
        else
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
        end
    end, "Clear all cursor")
    map("<C-j>", mc_feed("1Qj"), "Add cursor below")
    map("<C-k>", mc_feed("1Qk"), "Add cursor above")
    map("<C-n>", mc_match("*"), "Add cursor at next match")
    map("<C-p>", mc_match("#"), "Add cursor at prev match")
end

return M
