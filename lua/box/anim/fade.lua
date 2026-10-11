-- Fade effect: dissolve the whole window toward the editor background
-- (nvim-notify's `set_opacity` idea: blend the groups' fg/bg toward one
-- background colour).
--
-- Everything fades through ONE mechanism: a window-local highlight namespace
-- that redefines every group the window uses -- the window groups
-- (Normal/NormalNC for the text, NormalFloat for the float background,
-- FloatBorder/FloatTitle/FloatFooter for the border ring) and the style's
-- extmark groups (the fancy style draws icon/title/separator with extmarks).
--
-- Why not winhl remaps (the previous design): attaching a window-local
-- namespace makes nvim ignore the window's winhl *permanently* -- re-setting
-- the winhl afterwards (vim.wo or setwinvar, either order) does NOT revive it
-- (verified with screen-attr probes: without the ns a winhl colour change
-- renders, with the ns attached it never does). So the winhl-remap design
-- silently faded ONLY the extmark groups; the body text, background and border
-- never faded at all, which read as "the separator/title fade before the text".
-- The namespace alone can reach every one of those groups (verified: defining
-- Normal recolours the text, NormalFloat the float fill, FloatBorder the ring).
--
-- Namespaces cannot be deleted, so the ns instances live in a small reusable
-- slot pool; their definitions are reset when the fade ends.
local M = {}

local fade_pool, fade_next, fade_ns = {}, 0, {}
local function fade_slot()
    local slot = fade_next % 64 + 1
    for _ = 1, 64 do
        if not fade_pool[slot] then
            fade_pool[slot] = true
            fade_next = slot
            if not fade_ns[slot] then
                -- "fade2": namespaces cannot be deleted and an earlier
                -- implementation used "snacks_notif_fade_" with
                -- Normal/NormalFloat/... definitions; reusing that name would
                -- resurrect those stale definitions and break the window's
                -- colors
                fade_ns[slot] = vim.api.nvim_create_namespace("snacks_notif_fade2_" .. slot)
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
    -- body groups link to NormalFloat/Normal which may have no fg (transparent
    -- themes): fall back to the global Normal fg so the text still fades
    if not fg and name:match("^SnacksNotifier%w*$") then
        fg = Snacks.util.color("Normal", "fg")
    end
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

local function notif_fade_setup(win, contrast)
    if win._notif_fade then
        return win._notif_fade
    end
    local winhl = vim.wo[win.win].winhighlight
    if not winhl or winhl == "" then
        return nil
    end
    local target = Snacks.util.color("Normal", "bg")
        or Snacks.util.color("NormalFloat", "bg")
        or (vim.o.background == "light" and "#ffffff" or "#000000")
    local slot = fade_slot()
    if not slot then
        return nil
    end
    local fade = { slot = slot, ns = fade_ns[slot], target = target, winhl = winhl, groups = {}, last = {} }
    local ref -- the body group's contrast (the visibility reference)
    local ref_group
    -- window groups: redefine each winhl source in the namespace with the
    -- resolved attrs of its winhl target (Normal -> SnacksNotifierInfo etc.)
    for from, to in winhl:gmatch("([%w_]+):([%w_]+)") do
        local base = fade_base(to)
        if base then
            local g = { name = from, attrs = base.attrs, fg = base.fg, bg = base.bg }
            if from == "Normal" then
                ref = fade_contrast(g, target)
                ref_group = g
            end
            fade.groups[#fade.groups + 1] = g
        end
    end
    -- the float background / border ring
    local nf = fade_base("NormalFloat")
    if nf then
        fade.groups[#fade.groups + 1] = { name = "NormalFloat", attrs = nf.attrs, fg = nf.fg, bg = nf.bg }
    end
    -- extmark groups of the current style (icon/title/separator/footer)
    local suffix = winhl:match("Normal:SnacksNotifier(%w*)") or winhl:match("NormalNC:SnacksNotifier(%w*)")
    if suffix then
        for _, key in ipairs({ "Icon", "Title", "Border", "Footer" }) do
            local src = "SnacksNotifier" .. key .. suffix
            local base = fade_base(src)
            if base then
                fade.groups[#fade.groups + 1] = { name = src, attrs = base.attrs, fg = base.fg, bg = base.bg }
            end
        end
    end
    if #fade.groups == 0 then
        fade_pool[slot] = nil
        return nil
    end
    -- Contrast compensation: every group is blended by the same alpha, but the
    -- accents (separator/title/icon) differ from the body text both in
    -- luminance (this config: #61afef = 0.37 vs #abb2bf = 0.42) and in
    -- saturation. At uniform alpha the accents stay dimmer and vanish first;
    -- at a full luminance match they are equally bright but more saturated,
    -- so they linger. `contrast` is the strength: 1 = full luminance match,
    -- 0/false = uniform (nvim-notify), in between = split the difference.
    -- `set` bisects the alpha that hits the scaled target luminance, so the
    -- correction is exact rather than an approximation.
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
    vim.api.nvim_win_set_hl_ns(win.win, fade.ns)
    win._notif_fade = fade
    return fade
end

-- alpha 0 = blended into the editor background, 1 = the original colors
local function notif_fade_apply(win, alpha, contrast)
    local fade = win._notif_fade or notif_fade_setup(win, contrast)
    if not fade or not win:win_valid() then
        return
    end
    alpha = math.min(1, math.max(0, alpha))
    -- the body's current blended luminance: every matched group is bisected to
    -- the alpha that hits the same luminance (scaled by `strength`), so all
    -- groups track the body's visibility (the bisection is monotone; the
    -- clamp at 1 covers groups whose base is dimmer than the body)
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
            -- at full opacity -- measured: error's #e06c75 (L 0.279) against
            -- the body's #abb2bf (L 0.443) hit full colour at ~60% of the
            -- animation and then froze there while the body kept fading, which
            -- is the "separator/title are out of order" artefact, and it only
            -- showed up on error because warn (L 0.558) and info (L 0.394) stay
            -- close enough to the body to keep a solution all the way. Clamp
            -- the request to what the group can reach so it saturates on
            -- purpose. With `contrast` at 0 (the default here) none of this
            -- runs: every group shares one alpha, which keeps their
            -- brightness-above-the-background ratio constant, i.e. in sync.
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
        pcall(vim.api.nvim__redraw, { win = win.win, valid = false, flush = true })
    end
end

local function notif_fade_clear(win)
    local fade = win._notif_fade
    if not fade then
        return
    end
    win._notif_fade = nil
    if win:win_valid() then
        -- detaching the namespace leaves the winhl inert (see the header):
        -- re-assert the notifier's own winhl so the resting colors come back
        vim.api.nvim_win_set_hl_ns(win.win, 0)
        vim.wo[win.win].winhighlight = win.opts.wo.winhighlight or fade.winhl
    end
    for _, g in ipairs(fade.groups) do
        vim.api.nvim_set_hl(fade.ns, g.name, {})
    end
    fade_pool[fade.slot] = nil
end

---@param opts { frequency: number, damping?: number, settle: number, contrast?: boolean|number }
function M.new(opts)
    local sp = require("box.anim.spring").new(opts)
    local contrast = opts.contrast == nil and 0.5 or opts.contrast
    return {
        id = "fade",
        duration = sp.duration,
        easing = sp.easing,
        setup = function()
            return {}
        end,
        -- the width is not the progress here: alpha is the spring itself, so
        -- the fade is continuous instead of quantized by the integer width
        apply = function(win, _, p)
            notif_fade_apply(win, p, contrast)
        end,
        clear = function(win)
            notif_fade_clear(win)
        end,
    }
end

return M
