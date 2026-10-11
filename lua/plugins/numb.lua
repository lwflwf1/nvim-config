-- numb.nvim: preview the destination while typing `:15` / `:50,80d` on the cmdline,
-- so line jumps (and destructive range commands) are not blind. On confirm
-- (`<CR>`) it lands on the target and pushes the jumplist (so `<C-o>` still
-- returns); on abort (`<Esc>`) the window is restored untouched.
return {
    "nacro90/numb.nvim",
    -- Must be on the rtp (and its CmdlineChanged hook installed) before the
    -- FIRST cmdline, so it cannot be VeryLazy/UIEnter: you type `:` right after
    -- startup. Zero-dep pure-Lua plugin -> the tiny startup cost is the price
    -- of a reliable peek.
    lazy = false,
    opts = {
        -- "auto": peek in place when the target is on screen, float when it
        -- isn't, so far jumps don't yank the window off what you were reading
        -- (upstream default "window" always scrolls).
        peek_style = "auto",
    },
}
