-- Highlight groups this config owns: the ones the colorschemes don't define,
-- plus a few deliberate deviations from a plugin's own default. One table,
-- re-applied on every ColorScheme: a compiled colorscheme (onedarkpro's
-- included) opens with `hi clear`, which drops everything set outside it --
-- `default` groups too -- so a one-shot apply at plugin load is silently lost
-- after <leader>uC.
--
-- `default = true` means "only fill a hole, never override". Omit it where the
-- owning plugin declares the same group with `hi default` itself (the @org.*
-- keyword faces), or where we mean to override it (SnacksNotifier*): a default
-- set loses to a definition that is already there.
--
-- Theme-specific taste overrides stay in the colorscheme's own
-- `opts.highlights` (CursorLine, FloatTitle, @punctuation.bracket); picker
-- window surgery is box/picker_hl.lua, and the notifier animation is
-- box/notifier_anim.lua.
local M = {}

---The groups, resolved against whichever theme is currently loaded.
---@return table<string, table>
local function groups()
    return {
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

        -- aerial: the extra SymbolKinds registered in plugins/aerial.lua have no
        -- theme groups (onedarkpro's aerial.lua only carries AerialClass).
        AerialLine = { link = "IncSearch", default = true },
        AerialClockingIcon = { link = "Special", default = true },
        AerialBlockIcon = { link = "Special", default = true },
        AerialCovergroupIcon = { link = "Special", default = true },
        AerialAssertPropertyIcon = { link = "Special", default = true },
        AerialConstraintIcon = { link = "Special", default = true },
        AerialClocking = { link = "AerialNormal", default = true },
        AerialBlock = { link = "AerialNormal", default = true },
        AerialCovergroup = { link = "AerialNormal", default = true },
        AerialAssertProperty = { link = "AerialNormal", default = true },

        -- dropbar: Task is registered as a symbol kind in plugins/dropbar.lua,
        -- where it means the same thing as a function. The label groups are
        -- emptied on purpose so a Task symbol carries no color of its own.
        DropBarIconKindTask = { link = "Function", default = true },
        DropBarKindTask = { default = true },
        DropBarIconKindTaskNC = { link = "DropBarIconKindDefaultNC", default = true },
        DropBarKindTaskNC = { default = true },

        -- orgmode todo keywords and agenda, mapped onto the theme's own semantic
        -- groups (no hardcoded colors). orgmode declares the keyword faces with
        -- `hi default`, hence no `default` key on those.
        ["@org.keyword.face.TODO"] = { link = "DiagnosticError", bold = true },
        ["@org.keyword.face.NEXT"] = { link = "String", bold = true },
        ["@org.keyword.face.WAIT"] = { link = "DiagnosticWarn", bold = true },
        ["@org.keyword.face.HOLD"] = { link = "Comment", italic = true },
        ["@org.keyword.face.CANC"] = { link = "Comment", strikethrough = true },
        ["@org.keyword.face.DONE"] = { link = "String" },
        ["@org.agenda.day"] = { link = "Function", bold = true },
        ["@org.agenda.scheduled"] = { link = "String" },
        ["@org.agenda.deadline"] = { link = "DiagnosticError" },
        ["@org.agenda.time_grid"] = { link = "Comment" },
        ["@org.agenda.current_time"] = { link = "DiagnosticWarn", bold = true },
        -- The one group that needs a value rather than a link: the today chip
        -- takes its foreground from Statement and its background from Visual.
        -- A plain nvim_get_hl is safe even with a picker focused -- the picker's
        -- winhl remaps NormalFloat/FloatBorder/FloatTitle/FloatFooter/CursorLine
        -- only, none of which is read here. (That is why box/picker_hl.lua needs
        -- a hand-rolled link walker and this doesn't.)
        ["@org.agenda.today"] = {
            bold = true,
            fg = vim.api.nvim_get_hl(0, { name = "Statement" }).fg,
            bg = vim.api.nvim_get_hl(0, { name = "Visual" }).bg,
        },
    }
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