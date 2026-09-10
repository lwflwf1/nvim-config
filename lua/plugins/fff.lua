-- custom grep-match highlight: explicit bg/fg without reverse (IncSearch's
-- reverse attribute loses its background over NormalFloat extmarks, issue #646)
vim.api.nvim_set_hl(0, "FFFGrepMatch", { bg = "#6b4f2a", fg = "#ffcf5f", bold = true })

return {
    "dmtrKovalenko/fff",
    -- Downloads the prebuilt mlua shared library for this platform;
    -- falls back to cargo build if the download fails.
    build = function() require("fff.download").download_or_build_binary() end,
    lazy = false, -- the plugin lazy-initialises itself
    opts = {
        -- RHEL6 / Windows project trees live behind symlinks
        follow_symlinks = true,
        -- default prompt is the goose emoji (missing glyph in most fonts)
        prompt = "> ",
        -- custom grep-match highlight: explicit bg/fg without reverse
        -- (IncSearch's reverse attribute loses its background over
        -- NormalFloat extmarks, issue #646)
        hl = { grep_match = "FFFGrepMatch" },
        keymaps = {
            -- list replaces the default, so re-declare built-ins when adding
            move_up = { "<Up>", "<C-p>", "<C-k>" },
            move_down = { "<Down>", "<C-n>", "<C-j>" },
        },
    },
    keys = {
        { "<leader>ff", function() require("fff").find_files() end, desc = "Find files (fff)" },
        { "<leader>fz", function() require("fff").live_grep() end, desc = "Live grep (fff)" },
        { "<leader>fw", function() require("fff").live_grep_under_cursor() end, mode = { "n", "x" }, desc = "Search current word/selection (fff)" },
    },
    config = function(_, opts)
        require("fff").setup(opts)

        -- Upstream scroll_to_line uses `normal! zt` (match line pinned to the
        -- TOP of the preview) despite computing a centered offset above it.
        -- Re-center the match line instead.
        local preview = require("fff.file_picker.preview")
        preview.scroll_to_line = function(line)
            if not preview.state.winid or not vim.api.nvim_win_is_valid(preview.state.winid) then return end
            if not preview.state.bufnr or not vim.api.nvim_buf_is_valid(preview.state.bufnr) then return end
            local win_height = vim.api.nvim_win_get_height(preview.state.winid)
            local buffer_lines = vim.api.nvim_buf_line_count(preview.state.bufnr)
            local target_line = math.max(1, math.min(line, buffer_lines))
            preview.state.scroll_offset = math.max(0, target_line - math.floor(win_height / 2))
            pcall(vim.api.nvim_win_call, preview.state.winid, function()
                vim.api.nvim_win_set_cursor(preview.state.winid, { target_line, 0 })
                vim.cmd("normal! zz")
            end)
        end

        -- The preview window is recreated on every open with cursorline=false
        -- hardcoded, leaving the current match line unhighlighted. Re-enable it
        -- after each open (cursor sits on the match line via scroll_to_line).
        vim.api.nvim_create_autocmd("User", {
            pattern = "FFFOpen",
            callback = function()
                vim.defer_fn(function()
                    if preview.state.winid and vim.api.nvim_win_is_valid(preview.state.winid) then
                        vim.wo[preview.state.winid].cursorline = true
                    end
                end, 50)
            end,
        })
    end,
}
