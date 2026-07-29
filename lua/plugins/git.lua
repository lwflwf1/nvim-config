return {
    {
        "NeogitOrg/neogit",
        dependencies = {
            "nvim-lua/plenary.nvim",
        },
        cmd = "Neogit",
        opts = {
            disable_signs = false,
            disable_context_highlighting = false,
            disable_commit_confirmation = false,
            kind = "tab",
            integrations = { diffview = true },
        },
        keys = {
            { "<leader>gg", ":Neogit<CR>", desc = "Neogit (status)" },
        },
    },
    {
        "lewis6991/gitsigns.nvim",
        event = { "BufReadPre", "BufNewFile" },
        keys = {
            { "<leader>gj", "<cmd>Gitsigns nav_hunk next<CR>", desc = "Next hunk" },
            { "<leader>gk", "<cmd>Gitsigns nav_hunk prev<CR>", desc = "Prev hunk" },
            { "<leader>gh", "<cmd>Gitsigns preview_hunk<CR>", desc = "Preview hunk" },
            { "<leader>gH", "<cmd>Gitsigns preview_hunk_inline<CR>", desc = "Preview hunk inline" },
            { "<leader>gs", "<cmd>Gitsigns stage_hunk<CR>", desc = "Stage hunk" },
            { "<leader>gS", "<cmd>Gitsigns stage_buffer<CR>", desc = "Stage buffer" },
            { "<leader>gu", "<cmd>Gitsigns reset_hunk<CR>", desc = "Reset hunk" },
            { "<leader>gU", "<cmd>Gitsigns reset_buffer<CR>", desc = "Reset buffer" },
            { "<leader>gb", "<cmd>Gitsigns blame_line<CR>", desc = "Blame line" },
            { "<leader>gB", "<cmd>Gitsigns blame<CR>", desc = "Blame file" },
            { "<leader>ga", "<cmd>Gitsigns toggle_current_line_blame<CR>", desc = "Toggle line blame" },
            { "<leader>gw", "<cmd>Gitsigns toggle_word_diff<CR>", desc = "Toggle word diff" },
            { "<leader>gn", "<cmd>Gitsigns toggle_numhl<CR>", desc = "Toggle numhl" },
            { "<leader>gl", "<cmd>Gitsigns toggle_linehl<CR>", desc = "Toggle linehl" },

            { "ih", "<cmd>Gitsigns select_hunk<CR>", desc = "Inner hunk", mode = { "o", "x" } },
            { "ah", "<cmd>Gitsigns select_hunk<CR>", desc = "Around hunk", mode = { "o", "x" } },
        },
        config = function(_, opts)
            require("gitsigns").setup(opts)
            local hl = vim.api.nvim_set_hl
            hl(0, 'GitSignsStagedAdd',    { link = 'GitSignsAdd' })
            hl(0, 'GitSignsStagedChange', { link = 'GitSignsChange' })
            hl(0, 'GitSignsStagedDelete', { link = 'GitSignsDelete' })
            hl(0, 'GitSignsStagedAddNr',    { link = 'GitSignsAddNr' })
            hl(0, 'GitSignsStagedChangeNr', { link = 'GitSignsChangeNr' })
            hl(0, 'GitSignsStagedDeleteNr', { link = 'GitSignsDeleteNr' })
        end,
        opts = {
            signs = {
                add          = { text = "╎" },
                change       = { text = "╎" },
                delete       = { text = "_" },
                topdelete    = { text = "‾" },
                changedelete = { text = "╎" },
                untracked    = { text = "┆" },
            },
            signs_staged = {
                add          = { text = "┃" },
                change       = { text = "┃" },
                delete       = { text = "━" },
                topdelete    = { text = "━" },
                changedelete = { text = "┃" },
                untracked    = { text = "┆" },
            },
            numhl = true,
            on_attach = function(bufnr)
                vim.keymap.set("n", "<leader>gq", function()
                    local gs = require("gitsigns")
                    gs.quickfix()
                    vim.cmd.copen()
                end, { buffer = bufnr, desc = "Git quickfix" })
            end,
        },
    },
    {
        "sindrets/diffview.nvim",
        cmd = { "DiffviewOpen", "DiffviewFileHistory" },
        keys = {
            {
                "<leader>gv",
                function()
                    local lib = require("diffview.lib")
                    local view = lib.get_current_view()
                    if view then
                        vim.cmd("DiffviewClose")
                    else
                        vim.cmd("DiffviewOpen")
                    end
                end,
                desc = "Diffview toggle",
            },
            { "<leader>gf", "<cmd>DiffviewFileHistory<CR>", desc = "Diffview history" },
            { "<leader>gt", "<cmd>DiffviewToggleFiles<CR>", desc = "Diffview toggle files" },
        },
        opts = {},
    },
}
