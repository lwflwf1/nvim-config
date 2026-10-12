-- Snacks patch: picker windows must show the float background everywhere.
--
-- Their winhl only remaps NormalFloat, so any cell whose group has no bg of its
-- own falls back to the window's Normal (not remapped) and shows the editor
-- background instead of the float's. Two halves: remap Normal per picker window,
-- and strip the editor bg from the two groups that carry it explicitly
-- (LineNr/NonText, see onedarkpro's editor.lua) so everything linking them
-- falls back too.
--
-- Also styles the notifier-history winbar, which is not a picker window and so
-- gets no winhl remap. The notifier body groups themselves are in box/hl.lua.
--
-- Installed from plugins/snacks.lua's config() -- it needs Snacks on the rtp.
local M = {}

local function raw(group)
    return vim.api.nvim_get_hl(0, { name = group })
end

-- follow links manually: nvim_get_hl(link = false) resolves through the current
-- window's winhighlight, which corrupts resolution while a picker window is
-- focused
local function resolved(group, attr)
    local h = raw(group)
    local seen = {}
    while h.link and not seen[h.link] do
        seen[h.link] = true
        h = raw(h.link)
    end
    return h[attr] and ("#%06x"):format(h[attr]) or nil
end

local wrapped ---@type fun(prefix: string, links: table): string?

local function patch_winhl()
    local picker_hl = require("snacks").picker.highlight
    -- already ours: `:Lazy reload snacks.nvim` re-runs config(), and wrapping
    -- twice would append ",Normal:.." once per reload. Comparing identity (not
    -- a flag) also re-wraps correctly when snacks comes back as a fresh module.
    if picker_hl.winhl == wrapped then
        return
    end
    local orig_winhl = picker_hl.winhl
    wrapped = function(prefix, links)
        local ret = orig_winhl(prefix, links)
        -- the box window already maps Normal:SnacksNormal, and SnacksNormal
        -- links to NormalFloat, so it needs no remap
        if prefix ~= "SnacksPickerBox" then
            ret = ret .. ",Normal:" .. prefix
        end
        return ret
    end
    picker_hl.winhl = wrapped
end

local function apply()
    local float_bg = resolved("NormalFloat", "bg")
    local title_fg = resolved("Title", "fg")
    Snacks.util.set_hl({
        SnacksTitle  = { fg = title_fg, bg = float_bg },
        SnacksFooter = { fg = title_fg, bg = float_bg },
    }, { managed = false })
    -- strip the editor bg from the two source groups (keep fg and other attrs):
    -- the editor looks identical (fallback = Normal bg) and every group linking
    -- them now falls back to the window's float bg
    for _, name in ipairs({ "LineNr", "NonText" }) do
        local h = raw(name)
        h.bg = nil
        vim.api.nvim_set_hl(0, name, h)
    end
    -- the one group linking Normal: winhl remaps happen before link resolution,
    -- so the Normal: remap above can't reach it; flatten to fg only and let the
    -- bg fall back
    vim.api.nvim_set_hl(0, "SnacksPickerIconFile", { fg = resolved("Normal", "fg") })
end

function M.setup()
    patch_winhl()
    apply()
    -- `managed = false` above opts out of snacks' own re-apply (snacks_util_hl),
    -- so this has to replay after every `hi clear` itself.
    vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("box_picker_hl", { clear = true }),
        callback = function()
            vim.schedule(apply)
        end,
    })
end

return M