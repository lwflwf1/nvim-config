if not vim.g.neovide then
    return
end

vim.o.guifont = "JetBrainsMono Nerd Font Mono:h15"

-- option key as meta (matches kitty's macos_option_as_alt left)
vim.g.neovide_input_macos_option_key_is_meta = "only_left"

-- renderer-side animations (vsync'd; terminal nvim can't do these)
vim.g.neovide_scroll_animation_length = 0.3
vim.g.neovide_scroll_animation_far_lines = 9999
vim.g.neovide_position_animation_length = 0.15
vim.g.neovide_cursor_animation_length = 0.15
vim.g.neovide_cursor_trail_size = 0
vim.g.neovide_cursor_animate_in_insert_mode = true
vim.g.neovide_cursor_animate_command_line = true

-- kitty-like translucent + blurred look
vim.g.neovide_opacity = 0.9
vim.g.neovide_window_blurred = true
-- a translucent float always gets the backdrop blur
-- (need_blur = has_transparency || floating_blur), so tune the amount instead
vim.g.neovide_floating_blur_amount_x = 3.0
vim.g.neovide_floating_blur_amount_y = 3.0

-- simple fullscreen keeps the window on the desktop space, so transparency/blur
-- survive; native fullscreen (green button / cmd+ctrl+f) has nothing behind it
vim.g.neovide_macos_simple_fullscreen = true

-- cmd shortcuts (kitty handled these; Neovide does not)
vim.keymap.set({ "n", "i", "v" }, "<D-s>", "<Cmd>write<CR>", { desc = "Save" })
vim.keymap.set("v", "<D-c>", '"+y', { silent = true, desc = "Copy" })
for _, mode in ipairs({ "n", "i", "v", "c", "t" }) do
    vim.keymap.set(mode, "<D-v>", function()
        vim.api.nvim_paste(vim.fn.getreg("+"), true, -1)
    end, { silent = true, desc = "Paste" })
end
vim.keymap.set("n", "<D-S-f>", function()
    vim.g.neovide_macos_simple_fullscreen = not vim.g.neovide_macos_simple_fullscreen
end, { desc = "Toggle simple fullscreen" })
