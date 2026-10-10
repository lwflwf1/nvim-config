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

    -- Colorscheme picker with live preview. Final choice is persisted by the
    -- VimLeavePre hook above, so the picked theme becomes the default on next
    -- start.
    vim.keymap.set("n", "<leader>uC", function()
        Snacks.picker.colorschemes()
    end, { noremap = true, silent = true, desc = "Colorscheme picker" })
end

-- lualine theme helpers (moved from plugins/ui.lua's lualine spec).

--- Same shading bufferline applies to its bar: Normal bg tinted -25% (dark
--- themes) or -12% (bright themes), see bufferline/colors.lua color_is_bright +
--- shade_color. Kept in sync with the resulting BufferLineFill/BufferLineBuffer.
---@return string|nil
function M.shaded_normal_bg()
    local normal_bg = vim.api.nvim_get_hl(0, { name = "Normal" }).bg
    if not normal_bg then
        return nil
    end
    local r = math.floor(normal_bg / 0x10000) % 0x100
    local g = math.floor(normal_bg / 0x100) % 0x100
    local b = normal_bg % 0x100
    local bright = (0.299 * r + 0.587 * g + 0.114 * b) / 255 > 0.5
    local pct = bright and 88 or 75
    return ("#%02x%02x%02x"):format(
        math.floor(r * pct / 100),
        math.floor(g * pct / 100),
        math.floor(b * pct / 100)
    )
end

--- lualine theme: the preset's per-mode colors with every section background
--- darkened to match the bufferline bar (see shaded_normal_bg). Each mode's
--- a-section color moves from bg to fg, so the mode icon keeps its preset color
--- on the unified background.
---@return string|table
function M.theme_unified()
    local ok, theme = pcall(require("lualine.utils.loader").load_theme, "auto")
    if not ok or type(theme) ~= "table" then
        return "auto"
    end
    local normal = vim.api.nvim_get_hl(0, { name = "Normal" })
    if not normal.bg then
        return theme
    end
    local bg = M.shaded_normal_bg()
    local fg = normal.fg and ("#%06x"):format(normal.fg) or nil
    for mode, sections in pairs(theme) do
        if mode ~= "inactive" and type(sections) == "table" then
            if type(sections.a) == "table" then
                sections.a.fg = sections.a.bg or fg
            end
            for _, section in pairs(sections) do
                if type(section) == "table" then
                    section.bg = bg
                end
            end
        end
    end
    return theme
end

return M
