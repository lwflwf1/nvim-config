-- Press-a-letter window picker: draws one letter in the center of every
-- visible window and waits for that key. Returns the chosen window or nil
-- when cancelled. Self-contained on purpose -- snacks' pick_win only lists
-- non-floating windows and its default filter hides `snacks*` filetypes
-- (exactly the terminal windows this is used from), and its "current main"
-- logic (`snacks/picker/core/main.lua`) refuses non-file buffers.
local M = {}

local CHARS = "asdfghjkl"

---@param opts? { filter?: fun(win: number, buf: number): boolean }
---@return number|nil chosen window, nil when cancelled
function M.pick(opts)
    opts = opts or {}

    -- Snapshot the candidates before creating any overlay of our own.
    local wins = {}
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local buf = vim.api.nvim_win_get_buf(win)
        local cfg = vim.api.nvim_win_get_config(win)
        local visible = cfg.relative == "" or not cfg.hidden
        -- Skip the picker's own windows (paranoia: its close may be deferred).
        local picker_win = vim.w[win].snacks_layout ~= nil
            or vim.bo[buf].filetype:find("^snacks_picker") ~= nil
        if visible and cfg.focusable ~= false and not picker_win
            and (not opts.filter or opts.filter(win, buf)) then
            wins[#wins + 1] = win
        end
    end
    if #wins == 0 then return end
    if #wins == 1 then return wins[1] end

    local overlays = {}
    local by_char = {}
    for i, win in ipairs(wins) do
        local char = CHARS:sub(i, i)
        if char == "" then break end
        by_char[char] = win
        local ww, wh = vim.api.nvim_win_get_width(win), vim.api.nvim_win_get_height(win)
        local width, height = math.min(7, ww), math.min(3, wh)
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "", "   " .. char .. "   ", "" })
        local ok, owin = pcall(vim.api.nvim_open_win, buf, false, {
            relative = "win",
            win = win,
            width = width,
            height = height,
            row = math.max(0, math.floor((wh - height) / 2)),
            col = math.max(0, math.floor((ww - width) / 2)),
            style = "minimal",
            focusable = false,
            noautocmd = true,
            zindex = 50,
        })
        if ok then
            overlays[#overlays + 1] = { win = owin, buf = buf }
        end
    end

    vim.cmd("redraw!")
    local char = vim.fn.getcharstr()
    for _, o in ipairs(overlays) do
        pcall(vim.api.nvim_win_close, o.win, true)
        pcall(vim.api.nvim_buf_delete, o.buf, { force = true })
    end
    return by_char[char]
end

return M
