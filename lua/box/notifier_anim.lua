-- Notifier enter/exit animation: two independent effects from box/anim (which
-- is generic -- see box/anim/init.lua -- this file is only the notifier's
-- config). `slide` unfolds the width (right edge fixed), `fade` dissolves the
-- highlight groups toward the editor background. Both are optional: flip
-- `enable` (or replace the whole table with `false`) to see the other alone.
--
-- Spring parameters follow nvim-notify (frequency in Hz + damping ratio, and
-- `settle` = the fraction of the distance the spring covers when the schedule
-- ends -- the rest snaps, the perceptual cutoff nvim-notify applies with its
-- `complete` predicates). Each effect keeps its own progress, so the fade is
-- no longer quantized by the integer width.
local CONFIG = {
    fps = 120,
    id = "snacks_notifier", -- Snacks.animate id prefix (also the key that makes
    -- a restart replace the previous run on the same window)
    slide = {
        enable = true, -- false = dissolve only
        frequency = 3.5, -- ~250ms at settle 0.973 (k~=5.5, the previous spring)
        damping = 1,
        settle = 0.973,
        sweep = 40, -- cells swept on enter (math.huge = from a 2-cell sliver)
        sweep_out = math.huge, -- exit keeps the full shrink: a short sweep keeps
        -- the window wide through the low-alpha tail, which exposes the fade's
        -- border-before-text order (see the comment in box/anim/slide.lua)
        min = 2,
    },
    fade = {
        enable = true, -- false = unfold only
        frequency = 3.5,
        damping = 1,
        settle = 0.973, -- same spring as slide: the fade ends with the width,
        -- masking its integer tail (and the end-snap is 2.7%, not 4%)
        contrast = 0, -- luminance-match strength for the accents (separator/title/
        -- icon/footer). 0 = every group shares one alpha, which keeps each
        -- accent's brightness-above-the-background ratio CONSTANT through the
        -- animation, i.e. genuinely in sync (measured drift: info 0.03, warn
        -- 0.11, error 0.05). > 0 bisects each accent toward the body's
        -- luminance, but a group cannot outshine its own full colour, so an
        -- accent darker than the text saturates early and then freezes --
        -- measured: error's #e06c75 (L 0.279) vs the body's #abb2bf (L 0.443)
        -- reached full colour at ~60% and stopped, which desynchronised the
        -- separator/title on error only (warn L 0.558 and info L 0.394 are
        -- close enough to the body to keep a solution throughout). Raise only
        -- if the accents ever look too dim; 1 = full luminance match --
        -- box/anim/fade.lua
    },
}
return { notifier_animate_in = require("box.anim").attach(CONFIG) }
