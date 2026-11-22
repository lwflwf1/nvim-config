-- Highlight groups this config owns: the ones the colorschemes don't define,
-- plus a few deliberate deviations from a plugin's own default. One table,
-- re-applied on every ColorScheme: a compiled colorscheme (onedarkpro's
-- included) opens with `hi clear`, which drops everything set outside it --
-- `default` groups too -- so a one-shot apply at plugin load is silently lost
-- after <leader>uC.
--
-- `default = true` means "only fill a hole, never override". Omit it where the
-- owning plugin declares the same group with `hi default` itself, or where we
-- mean to override it (SnacksNotifier*): a default set loses to a definition
-- that is already there.
--
-- Theme-specific taste overrides stay in the colorscheme's own
-- `opts.highlights` (CursorLine, FloatTitle, @punctuation.bracket); picker
-- window surgery is box/picker_hl.lua, and the notifier animation is
-- box/notifier_anim.lua.
local M = {}

---The groups, resolved against whichever theme is currently loaded.
---@return table<string, table>
local function groups()
    local g = {
        -- blink.cmp and onedarkpro's blink_cmp.lua both omit these 4 kinds, so
        -- the icon and the kind label fall back to the menu foreground.
        -- blink sets every group with `default = true`, so ours win either way.
        BlinkCmpKindVariable = { link = "Identifier" },
        BlinkCmpKindFolder = { link = "Directory" },
        BlinkCmpKindReference = { link = "Tag" },
        BlinkCmpKindColor = { link = "Constant" },
        -- ...and the label detail/description groups are omitted too, landing on
        -- PmenuExtra (which has no fg of its own) without use_nvim_cmp_as_default.
        BlinkCmpLabelDetail = { link = "BlinkCmpSource" },
        BlinkCmpLabelDescription = { link = "BlinkCmpSource" },

        -- not a gap: snacks links the notifier body to Normal, but a
        -- notification is a float, so a Normal bg would show the editor
        -- background inside the float's border. Override on purpose.
        SnacksNotifierTrace = { link = "NormalFloat" },
        SnacksNotifierDebug = { link = "NormalFloat" },
        SnacksNotifierInfo = { link = "NormalFloat" },
        SnacksNotifierWarn = { link = "NormalFloat" },
        SnacksNotifierError = { link = "NormalFloat" },

        -- gitsigns builds the Staged names per sign (signs.lua) but defines none
        -- of them -- not even as defaults -- and onedarkpro's gitsigns.lua has no
        -- Staged groups either, so a staged hunk loses its color entirely.
        GitSignsStagedAdd = { link = "GitSignsAdd" },
        GitSignsStagedChange = { link = "GitSignsChange" },
        GitSignsStagedDelete = { link = "GitSignsDelete" },
        GitSignsStagedAddNr = { link = "GitSignsAddNr" },
        GitSignsStagedChangeNr = { link = "GitSignsChangeNr" },
        GitSignsStagedDeleteNr = { link = "GitSignsDeleteNr" },

    }

    -- aerial/dropbar groups this config owns. The custom SymbolKinds
    -- (registered in plugins/aerial.lua and dropbar.lua's sv_kinds) have no
    -- theme or plugin groups: aerial needs text + icon, dropbar needs text +
    -- icon plus the NC variants it only derives for kinds it already knows.
    -- { kind, aerial icon, dropbar icon }; a nil side is skipped (Clocking..
    -- Constraint are aerial-only, Task is dropbar-only). Net reuses Variable's
    -- highlight (Identifier / DropBarIconKindDefault).
    g.AerialLine = { link = "IncSearch", default = true }
    for _, spec in ipairs({
        { "Clocking",       "Special" },
        { "Block",          "Special" },
        { "Covergroup",     "Special" },
        { "AssertProperty", "Special" },
        { "Constraint",     "Special" },
        { "InputPort",      "Special",    "Special" },
        { "OutputPort",     "Special",    "Special" },
        { "InoutPort",      "Special",    "Special" },
        { "Port",           "Special",    "Special" },
        { "Net",            "Identifier", "DropBarIconKindDefault" },
        { "Task",           nil,          "Function" },
    }) do
        local kind, aerial_icon, dropbar_icon = spec[1], spec[2], spec[3]
        if aerial_icon then
            g["Aerial" .. kind .. "Icon"] = { link = aerial_icon, default = true }
            g["Aerial" .. kind] = { link = "AerialNormal", default = true }
        end
        if dropbar_icon then
            g["DropBarIconKind" .. kind] = { link = dropbar_icon, default = true }
            g["DropBarKind" .. kind] = { default = true }
            g["DropBarIconKind" .. kind .. "NC"] = { link = "DropBarIconKindDefaultNC", default = true }
            g["DropBarKind" .. kind .. "NC"] = { default = true }
        end
    end

    return g
end

function M.apply()
    for name, val in pairs(groups()) do
        vim.api.nvim_set_hl(0, name, val)
    end
end

function M.setup()
    vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("box_hl", { clear = true }),
        callback = M.apply,
    })
end

return M