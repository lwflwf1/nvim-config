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
}
