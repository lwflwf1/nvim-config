return {
    {
        "tpope/vim-fugitive",
        cmd = { "Git", "G", "Gdiffsplit", "Gread", "Gwrite", "Gstatus" },
        keys = {
            { "<leader>gw", ":Gwrite<CR>", desc = "Git write" },
            { "<leader>gr", ":Gread<CR>", desc = "Git read" },
            { "<leader>gd", ":Gdiffsplit @<CR>", desc = "Git diff" },
            { "<leader>gb", ":Git branch<CR>", desc = "Git branch" },
            { "<leader>gB", ":Git blame<CR>", desc = "Git blame" },
            { "<leader>gg", ":Git<CR>", desc = "Git status" },
            { "<leader>gl", ":Git log<CR>", desc = "Git log" },
            { "<leader>gp", ":Git pull<CR>", desc = "Git pull" },
            { "<leader>gP", ":Git push<CR>", desc = "Git push" },
            { "<leader>gc", ":Git commit<CR>", desc = "Git commit" },
            { "<leader>gA", ":Git commit --amend --no-edit<CR>", desc = "Git amend" },
            { "<leader>gs", ":Git stash<CR>", desc = "Git stash" },
            { "<leader>gS", ":Git stash pop<CR>", desc = "Git stash pop" },
        },
    },
    {
        "lewis6991/gitsigns.nvim",
        event = { "BufReadPre", "BufNewFile" },
        keys = {
            { "<leader>gj", "<cmd>Gitsigns next_hunk<CR>", desc = "Next hunk" },
            { "<leader>gk", "<cmd>Gitsigns prev_hunk<CR>", desc = "Prev hunk" },
            { "<leader>gh", "<cmd>Gitsigns preview_hunk<CR>", desc = "Preview hunk" },
            { "<leader>gu", "<cmd>Gitsigns undo_stage_hunk<CR>", desc = "Undo hunk" },
            { "<leader>ge", "<cmd>Gitsigns stage_hunk<CR>", desc = "Stage hunk" },
            { "<leader>gU", "<cmd>Gitsigns reset_hunk<CR>", desc = "Reset hunk" },
            { "<leader>gf", "<cmd>Gitsigns fold<CR>", desc = "Fold hunk" },

            { "ih", "<cmd>Gitsigns select_hunk<CR>", desc = "Inner hunk", mode = { "o", "x" } },
            { "ah", "<cmd>Gitsigns select_hunk<CR>", desc = "Around hunk", mode = { "o", "x" } },
        },
        opts = {
            signs = {
                add = { text = "+" },
                change = { text = "~" },
                delete = { text = "-" },
                topdelete = { text = "‾" },
                changedelete = { text = "~" },
            },
            signs_staged = {
                add = { text = "+" },
                change = { text = "~" },
                delete = { text = "-" },
                topdelete = { text = "‾" },
                changedelete = { text = "~" },
            },
            on_attach = function(bufnr)
                vim.keymap.set("n", "<leader>gq", function()
                    local gs = require("gitsigns")
                    gs.quickfix()
                    vim.cmd.copen()
                end, { buffer = bufnr, desc = "Git quickfix" })
            end,
        },
    },
}
