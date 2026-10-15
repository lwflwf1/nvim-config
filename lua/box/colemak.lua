-- Colemak-DH: keep hjkl on their QWERTY *physical* keys (<leader>uk, off by
-- default so a QWERTY install is untouched).
--
-- Under Colemak-DH ANSI these letters sit on different keys than on QWERTY.
-- Table from the official colemak_dh_ansi_us.klc: read its SC column against the
-- standard PC/AT set-1 scan codes (0x1e-0x27 is the home row, 0x28 is `'`,
-- 0x2b is `\`, 0x39 is space). Its VK_ column is NOT a position oracle -- it has
-- been rewritten to the produced character, so reading it shifts the bottom row
-- one key:
--
--     m@H  n@J  e@K  i@L      h@M  j@Y  k@N  l@U  u@I
--
-- So vim's `h` ends up on the M key and `m` on the H key, and hjkl is the one
-- thing worth fixing: every motion runs through it. This module translates the
-- produced letter back to the command its QWERTY key would have run, so the
-- motions land where QWERTY put them -- and the letters that got displaced
-- (h j k l, plus u/i which occupy each other's slots) get their QWERTY command
-- back, so nothing becomes unreachable.
--
-- Normal mode only, on purpose: `i`/`a` are prefixes for text objects in visual
-- and operator-pending mode, so remapping `i` there would break every `viw` /
-- `di(`. Insert mode is untouched, so typing is always plain Colemak-DH.
--
-- Scope is the hjkl neighbourhood. Deliberately NOT remapped: `y`, whose slot
-- moves too (Colemak-DH puts it on the O key), so the physical O key stays a
-- yank key.
--
-- Overlapping mappings are snapshotted and put back on disable rather than
-- declared, because `h`/`j`/`k`/`l` are not ours: hardtime rate-limits them with
-- an expr mapping wrapping a Lua callback (`restricted_keys` covers "n" and "x"),
-- and hardtime is `lazy = false`, so it installs them *after* box.setup().
-- Re-declaring `j`/`k` would silently kill hardtime's mapping for good, and a
-- re-declared mapping cannot be un-done. `maparg(..., true)` does hand back the
-- `callback`/`expr`/`silent` fields needed to rebuild it exactly.
local M = {}

local function d(desc)
    return { noremap = true, silent = true, desc = desc }
end

-- produced letter -> the command its QWERTY physical key runs.
--
-- "gj"/"gk" are spelled out rather than reaching core/keymaps.lua's `j`/`k`
-- mappings: the swap's right-hand side is noremap, so `n -> j` would run a
-- literal `j` (plain line down), not the display-line `gj` this config wants.
local COLEMAK_KEYMAPS = {
    -- the four motions back onto H J K L
    { "m", "h", "Left" },
    { "n", "gj", "Down (display lines)" },
    { "e", "gk", "Up (display lines)" },
    { "i", "l", "Right" },
    -- the keys they vacated, back to what QWERTY had there
    { "h", "m", "Set mark" },
    { "j", "y", "Yank line" },
    { "k", "n", "Next match" },
    { "l", "u", "Undo" },
    { "u", "i", "Insert" },
}

-- lhs -> maparg() dict describing whatever owned that key when we took it.
-- An empty dict means "nothing was mapped here".
local saved = {}

local function had_mapping(snap)
    return type(snap) == "table" and (snap.callback ~= nil or (snap.rhs ~= nil and snap.rhs ~= ""))
end

local function restore(lhs, snap)
    if not had_mapping(snap) then
        pcall(vim.keymap.del, "n", lhs) -- E31 when it is not there
        return
    end
    -- `nowait` is dropped and a buffer-local snapshot would come back global;
    -- neither can bite, none of the nine keys is buffer-local here (the only
    -- buffer-local normal maps are gk/grd/grn/grl/K from box/lsp.lua, outside
    -- the set).
    local opts = { noremap = snap.noremap == 1, silent = snap.silent == 1 }
    if snap.expr == 1 then
        opts.expr = true
    end
    if snap.desc and snap.desc ~= "" then
        opts.desc = snap.desc
    end
    vim.keymap.set("n", lhs, snap.callback or snap.rhs, opts)
end

local function enable()
    for _, m in ipairs(COLEMAK_KEYMAPS) do
        -- `or` on the empty-dict case: an empty table is truthy, so a genuinely
        -- unmapped key is still recorded as "nothing was here"
        saved[m[1]] = saved[m[1]] or vim.fn.maparg(m[1], "n", false, true)
        vim.keymap.set("n", m[1], m[2], d(m[3]))
    end
    vim.g.colemak_keymaps = true
end

local function disable()
    for _, m in ipairs(COLEMAK_KEYMAPS) do
        restore(m[1], saved[m[1]])
    end
    saved = {}
    vim.g.colemak_keymaps = false
end

-- One Snacks.toggle behind <leader>uk, so snacks owns the "Enabled/Disabled"
-- notification and which-key's state-aware desc. Created on first use:
-- box.setup() runs before lazy.setup() (no Snacks yet), and the toggle's own
-- :map then replaces the plain keymap set below. Mirrors box/project.lua's
-- auto_cwd toggle.
local toggle

local function flip()
    if not toggle then
        toggle = Snacks.toggle.new({
            id = "colemak_keymaps",
            name = "Colemak-DH",
            get = function() return vim.g.colemak_keymaps end,
            set = function(state)
                if state then
                    enable()
                else
                    disable()
                end
            end,
        }):map("<leader>uk")
    end
    toggle:toggle()
end

function M.setup()
    vim.g.colemak_keymaps = false
    vim.keymap.set("n", "<leader>uk", flip, d("Toggle Colemak-DH hjkl"))
end

return M
