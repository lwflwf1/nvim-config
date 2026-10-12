-- Fade effect: dissolve the window toward the editor background (nvim-notify's
-- `set_opacity` idea: blend the groups' fg/bg toward one background colour).
--
-- Works on any float: the groups the window paints with are taken from the
-- window's own `winhighlight` (each `from:to` becomes `from` redefined in a
-- window-local namespace with `to`'s resolved colours), plus the float fill and
-- the border ring, plus any extra groups the caller lists (see `groups`) -- the
-- style's extmark groups, which winhl cannot reach.
--
-- Why a namespace and not winhl remaps: attaching a window-local namespace makes
-- nvim ignore the window's winhl *permanently* -- re-setting the winhl afterwards
-- (vim.wo or setwinvar, either order) does NOT revive it (verified with
-- screen-attr probes). An earlier version remapped winhl onto per-window private
-- groups and faded through that, which silently faded ONLY the extmark groups
-- (whichever groups winhl could not reach); the body text, background and border
-- never faded. The namespace alone reaches every one of them (verified: defining
-- Normal recolours the text, NormalFloat the fill, FloatBorder the ring).
--
-- Namespaces cannot be deleted, so the ns instances live in a small reusable
-- slot pool; their definitions are reset when the fade ends.
local M = {}

local fade_pool, fade_next, fade_ns = {}, 0, {}

---@type table<number, table>  per-window fade state, keyed by winid (the effect
--- instance is shared across windows, and raw floats have no Lua object to hang
--- state off)
local fades = {}

local function fade_slot()
    local slot = fade_next % 64 + 1
    for _ = 1, 64 do
        if not fade_pool[slot] then
            fade_pool[slot] = true
            fade_next = slot
            if not fade_ns[slot] then
                -- "box_anim_fade": namespaces cannot be deleted and earlier
                -- implementations used other names ("snacks_notif_fade_",
                -- "snacks_notif_fade2_") with different group definitions;
                -- reusing one would resurrect those stale definitions and break
                -- the window's colours
                fade_ns[slot] = vim.api.nvim_create_namespace("box_anim_fade_" .. slot)
            end
            return slot
        end
        slot = slot % 64 + 1
    end
    -- all 64 slots busy (unreachable in practice): skip the fade rather than
    -- alias a live slot, which would make two windows fight over one group
    return nil
end

---@param name string
---@return table? resolved attrs plus fg/bg as hex strings
local function fade_base(name)
    -- follow links manually from the raw definitions: nvim_get_hl's link
    -- resolution can be influenced by the current window's winhighlight
    local h = vim.api.nvim_get_hl(0, { name = name })
    local seen = {}
    while h and h.link and not seen[h.link] do
        seen[h.link] = true
        h = vim.api.nvim_get_hl(0, { name = h.link })
    end
    if not h then
        return nil
    end
    local attrs = {}
    for k, v in pairs(h) do
        if k ~= "default" and k ~= "link" then
            attrs[k] = v
        end
    end
    local fg = attrs.fg and string.format("#%06x", attrs.fg)
    local bg = attrs.bg and string.format("#%06x", attrs.bg)
    if not fg and not bg then
        return nil
    end
    return { attrs = attrs, fg = fg, bg = bg }
end

local function fade_blend(g, target, alpha)
    local hl = {}
    for k, v in pairs(g.attrs) do
        hl[k] = v
    end
    if g.fg then
        hl.fg = Snacks.util.blend(g.fg, target, alpha)
    end
    if g.bg then
        hl.bg = Snacks.util.blend(g.bg, target, alpha)
    end
    return hl
end

-- relative luminance (sRGB / WCAG) of a "#rrggbb" string, 0..1
local function fade_luminance(hex)
    local function lin(v)
        v = v / 255
        return v <= 0.04045 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4
    end
    return 0.2126 * lin(tonumber(hex:sub(2, 3), 16))
        + 0.7152 * lin(tonumber(hex:sub(4, 5), 16))
        + 0.0722 * lin(tonumber(hex:sub(6, 7), 16))
end

-- perceptual contrast of a group's fg/bg to the blend target. The eye weights
-- luminance, not max channel: this theme's blue accent (#61afef) is 1.35x the
-- text (#abb2bf) by max channel but only 1.12x by luminance, so a max-channel
-- metric over-corrects -- the accents then fade visibly faster than the text.
local function fade_contrast(g, target)
    local tl = fade_luminance(target)
    local c = 0
    for _, v in ipairs({ g.fg, g.bg }) do
        if v then
            c = math.max(c, math.abs(fade_luminance(v) - tl))
        end
    end
    return c
end

local function fade_rgb(hex)
    return { tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16) }
end

-- luminance of a colour blended toward the target by alpha (the blend happens
-- in sRGB space, as nvim renders it, so the result is not linear in alpha --
-- matching alphas by scaling would leave a visible offset)
local function fade_lum(rgb, target, alpha)
    local function lin(v)
        v = v / 255
        return v <= 0.04045 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4
    end
    return 0.2126 * lin(rgb[1] * alpha + target[1] * (1 - alpha))
        + 0.7152 * lin(rgb[2] * alpha + target[2] * (1 - alpha))
        + 0.0722 * lin(rgb[3] * alpha + target[3] * (1 - alpha))
end

---@param aw table animation window (see box/anim/core.lua)
---@param contrast number|boolean
---@param groups nil|string[]|fun(aw: table, winhl: string): string[]
local function fade_setup(aw, contrast, groups)
    local winid = aw.win
    if fades[winid] then
        return fades[winid]
    end
    local winhl = vim.wo[winid].winhighlight
    if not winhl or winhl == "" then
        return nil
    end
    -- Read the colours through fade_base, NOT Snacks.util.color: that helper
    -- uses nvim_get_hl(..., link = false), and that variant starts reflecting the
    -- CURRENT window's winhighlight once nvim has applied it (measured: identical
    -- to the plain read while synchronous, nil on the next tick). The animation
    -- always runs after ticks, so any window mapping Normal (every animated
    -- picker/input) got nil for the body fg and the editor bg came back as the
    -- card colour -- the fade became a no-op. The plain read (fade_base) is not
    -- affected.
    local norm = fade_base("Normal")
    local target = (norm and norm.bg)
        or (fade_base("NormalFloat") or {}).bg
        or (vim.o.background == "light" and "#ffffff" or "#000000")
    local slot = fade_slot()
    if not slot then
        return nil
    end
    local fade = { winid = winid, slot = slot, ns = fade_ns[slot], target = target, winhl = winhl, groups = {}, last = {}, seen = {} }

    --- add a group once, in priority order (winhl sources first, so a caller's
    --- `groups` can never displace the group the window actually paints with)
    local function add(name, base)
        if not base or fade.seen[name] then
            return
        end
        fade.seen[name] = true
        fade.groups[#fade.groups + 1] = { name = name, attrs = base.attrs, fg = base.fg, bg = base.bg }
    end

    local ref -- the body group's contrast (the visibility reference)
    local ref_group
    -- window groups: redefine each winhl source in the namespace with the
    -- resolved attrs of its winhl target (Normal -> SnacksNotifierInfo etc.)
    for from, to in winhl:gmatch("([%w_]+):([%w_]+)") do
        local base = fade_base(to)
        if base then
            -- a window group whose target carries only a background (linked to
            -- NormalFloat) has no fg of its own: nvim falls back to the global
            -- Normal for the window's normal text, so fade from there
            if not base.fg and (from == "Normal" or from == "NormalNC") then
                base.fg = norm and norm.fg
            end
            local g = { name = from, attrs = base.attrs, fg = base.fg, bg = base.bg }
            if from == "Normal" then
                ref = fade_contrast(g, target)
                ref_group = g
            end
            add(from, { attrs = base.attrs, fg = base.fg, bg = base.bg })
        end
    end
    -- the float fill, the border ring and the window's normal text/background,
    -- unless the winhl already remapped them. Normal/NormalNC matter because a
    -- window may remap only NormalFloat (Snacks.input does): its text still uses
    -- the global Normal, so without these the text would appear before the box.
    add("Normal", fade_base("Normal"))
    add("NormalNC", fade_base("NormalNC"))
    add("NormalFloat", fade_base("NormalFloat"))
    add("FloatBorder", fade_base("FloatBorder"))
    add("FloatTitle", fade_base("FloatTitle"))
    add("FloatFooter", fade_base("FloatFooter"))
    -- groups the window paints its own CONTENT with (extmarks: picker items and
    -- their icons, the notifier's title/separator, ...). Discovered from the
    -- visible range instead of enumerated per target, so a new window needs no
    -- config at all. Syntax/treesitter highlights are not extmarks, so content
    -- styled only by syntax (e.g. the picker preview) cannot fade from here --
    -- pass `groups` for whatever this misses.
    if aw.buf then
        local first, last = 0, -1
        pcall(vim.api.nvim_win_call, winid, function()
            first, last = vim.fn.line("w0") - 1, vim.fn.line("w$")
        end)
        -- start/end are (row, col) tuples -- a bare integer is read as an
        -- extmark id, which silently found nothing (nvim: "Invalid mark id")
        local ok, marks = pcall(vim.api.nvim_buf_get_extmarks, aw.buf, -1, { first, 0 }, { last, 0 }, { details = true })
        if ok then
            for _, m in ipairs(marks) do
                local d = m[4]
                if d then
                    if d.hl_group then
                        add(d.hl_group, fade_base(d.hl_group))
                    end
                    if d.virt_text then
                        for _, chunk in ipairs(d.virt_text) do
                            if chunk[2] then
                                add(chunk[2], fade_base(chunk[2]))
                            end
                        end
                    end
                end
            end
        end
    end
    -- the float's border title/footer are chunk lists that carry their own
    -- highlight groups (Snacks.input draws its prompt/icon there), which winhl
    -- does not reach
    local conf = vim.api.nvim_win_get_config(winid)
    for _, side in ipairs({ "title", "footer" }) do
        local chunks = conf[side]
        if type(chunks) == "table" then
            for _, chunk in ipairs(chunks) do
                local hl = type(chunk) == "table" and chunk[2]
                if type(hl) == "string" and hl ~= "" then
                    add(hl, fade_base(hl))
                end
            end
        end
    end
    -- `%#Group#` segments in winbar/statuscolumn carry their own groups too
    -- (Snacks.input draws its icon in the statuscolumn, the notifier history in
    -- the winbar), which winhl does not reach
    for _, opt in ipairs({ "winbar", "statuscolumn" }) do
        local val = vim.wo[winid][opt]
        if type(val) == "string" then
            for g in val:gmatch("%%#([^#]+)#") do
                add(g, fade_base(g))
            end
        end
    end
    -- groups the caller lists explicitly (for anything the scan misses)
    if type(groups) == "function" then
        groups = groups(aw, winhl)
    end
    if type(groups) == "table" then
        for _, name in ipairs(groups) do
            add(name, fade_base(name))
        end
    end
    if #fade.groups == 0 then
        fade_pool[slot] = nil
        return nil
    end
    -- Contrast compensation: every group is blended by the same alpha, but the
    -- accents differ from the body text both in luminance and in saturation. At
    -- uniform alpha the accents stay dimmer and vanish first; at a full luminance
    -- match they are equally bright but more saturated, so they linger.
    -- `contrast` is the strength: 1 = full luminance match, 0/false = uniform
    -- (nvim-notify), in between = split the difference.
    local strength = contrast == true and 1 or (tonumber(contrast) or 0)
    -- clamp to 0..2: the knob is a strength multiplier on the correction, but
    -- values above 2 would extrapolate past the bisection's bracket and make
    -- accents brighter than the body text (visibly wrong, not just "more")
    strength = math.min(2, math.max(0, strength))
    if strength > 0 and ref and ref > 0 and ref_group then
        fade.target_rgb = fade_rgb(target)
        fade.ref_rgb = fade_rgb(ref_group.fg or ref_group.bg)
        fade.strength = strength
        for _, g in ipairs(fade.groups) do
            if g ~= ref_group and fade_contrast(g, target) >= ref * 0.25 then
                g.rgb = fade_rgb(g.fg or g.bg)
                -- brighter than the target? (the bisection's direction)
                g.up = fade_lum(g.rgb, fade.target_rgb, 1) > fade_lum(g.rgb, fade.target_rgb, 0)
            end
        end
    end
    vim.api.nvim_win_set_hl_ns(winid, fade.ns)
    fades[winid] = fade
    return fade
end

-- alpha 0 = blended into the editor background, 1 = the original colors
local function fade_apply(aw, alpha, contrast, groups)
    local fade = fades[aw.win] or fade_setup(aw, contrast, groups)
    if not fade or not aw.valid() then
        return
    end
    alpha = math.min(1, math.max(0, alpha))
    -- the body's current blended luminance: every matched group is bisected to
    -- the alpha that hits the same luminance (scaled by `strength`), so all
    -- groups track the body's visibility
    local want
    if fade.ref_rgb then
        want = fade_lum(fade.ref_rgb, fade.target_rgb, alpha)
    end
    -- only rewrite a group when its blended colours actually moved (nvim-notify
    -- tracks an `updated` flag the same way); the remaining attrs are constant
    for _, g in ipairs(fade.groups) do
        local a = alpha
        if want and g.rgb then
            -- A group can never get brighter than its own full colour, so a
            -- target above that has no solution in [0,1]. Left unbounded the
            -- bisection silently collapses onto an endpoint and pins the group
            -- at full opacity -- measured: error's #e06c75 (L 0.279) against the
            -- body's #abb2bf (L 0.443) hit full colour at ~60% of the animation
            -- and then froze there while the body kept fading. Clamp the request
            -- to what the group can reach so it saturates on purpose.
            local w = math.min(want, fade_lum(g.rgb, fade.target_rgb, 1))
            local lo, hi = 0, 1
            for _ = 1, 12 do
                local mid = (lo + hi) / 2
                local below = fade_lum(g.rgb, fade.target_rgb, mid) < w
                if below == g.up then
                    lo = mid
                else
                    hi = mid
                end
            end
            a = alpha + (lo - alpha) * fade.strength
        end
        local hl = fade_blend(g, fade.target, a)
        local last = fade.last[g.name]
        if last and last.fg == hl.fg and last.bg == hl.bg then
            goto continue
        end
        fade.last[g.name] = { fg = hl.fg, bg = hl.bg }
        vim.api.nvim_set_hl(fade.ns, g.name, hl)
        ::continue::
    end
    -- flush per frame (like the slide): without it the highlight updates sit in
    -- nvim's cache until some unrelated redraw happens, so the fade renders as
    -- freeze-then-jump -- and with the slide disabled there is no other flusher
    if vim.api.nvim__redraw then
        pcall(vim.api.nvim__redraw, { win = aw.win, valid = false, flush = true })
    end
end

local function fade_clear(aw)
    local fade = fades[aw.win]
    if not fade then
        return
    end
    fades[aw.win] = nil
    if aw.valid() then
        -- detaching the namespace leaves the winhl inert (see the header):
        -- re-assert the window's own winhl so the resting colours come back
        vim.api.nvim_win_set_hl_ns(aw.win, 0)
        vim.wo[aw.win].winhighlight = fade.winhl
    end
    for _, g in ipairs(fade.groups) do
        vim.api.nvim_set_hl(fade.ns, g.name, {})
    end
    fade_pool[fade.slot] = nil
end

---@param opts { frequency: number, damping?: number, settle: number, contrast?: boolean|number, groups?: string[]|fun(aw: table, winhl: string): string[] }
function M.new(opts)
    local sp = require("box.anim.spring").new(opts)
    local contrast = opts.contrast == nil and 0.5 or opts.contrast
    local groups = opts.groups
    return {
        id = "fade",
        duration = sp.duration,
        easing = sp.easing,
        setup = function()
            return {}
        end,
        -- the width is not the progress here: alpha is the spring itself, so
        -- the fade is continuous instead of quantized by the integer width
        apply = function(aw, _, p)
            fade_apply(aw, p, contrast, groups)
        end,
        clear = function(aw)
            fade_clear(aw)
        end,
    }
end

return M
