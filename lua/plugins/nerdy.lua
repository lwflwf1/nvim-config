return {
    "2KAbhishek/nerdy.nvim",
    -- Glyph picker: fuzzy-find nerd-font icons and insert them at the cursor.
    -- Picker UI is snacks (already loaded at priority 1000), so multi-select
    -- (<Tab>/<S-Tab>, <C-a>) works through snacks' picker.
    dependencies = { "folke/snacks.nvim" },
    cmd = { "Nerdy" },
    keys = {
        { "<leader>fi", "<cmd>Nerdy list<CR>",    desc = "Find nerd icon and insert" },
    },
    opts = {
        picker = "snacks", -- pin instead of 'auto': deterministic picker choice
        max_recents = 30,
    },
}
