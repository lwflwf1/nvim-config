-- Enter/exit animation for Snacks.input (the one-line prompt: `vim.ui.input`,
-- the picker rename/replace prompts, ...). box/anim is generic -- this file is
-- only the input's config, wired from plugins/snacks.lua via
-- `styles.input.on_win` (that style has no internal on_win, unlike the picker's
-- windows, whose on_win belongs to snacks).
local CONFIG = {
    fps = 120,
    id = "snacks_input", -- Snacks.animate id prefix; also the restart key
    -- a bit quicker than the notifier: a prompt should feel snappy
    slide = {
        enable = false, -- fade only (the fade flushes its own frames, so it
        -- still paints every step with the slide off)
        frequency = 4.5,
        damping = 1,
        settle = 0.973,
        sweep = 24, -- a short unfold; the box is only one line tall
        sweep_out = math.huge, -- exit keeps the full shrink (hides the fade tail)
        min = 2,
    },
    fade = {
        enable = true, -- false = unfold only
        frequency = 4.5,
        damping = 1,
        settle = 0.973,
        contrast = 0, -- uniform alpha: every group fades together
    },
}
return { input_animate_in = require("box.anim").attach(CONFIG) }
