return {
    "folke/todo-comments.nvim",
    event = "VeryLazy",
    dependencies = { "nvim-lua/plenary.nvim" },
    keys = {
        { "<leader>tf", "<cmd>TodoTelescope<CR>", desc = "TODOs search in Telescope" },
        { "<leader>tq", "<cmd>TodoQuickFix<CR>", desc = "TODOs to quickfix" },
        { "<leader>tn", "<cmd>lua require('todo-comments').jump_next()<CR>", desc = "Next TODO" },
        { "<leader>tp", "<cmd>lua require('todo-comments').jump_prev()<CR>", desc = "Prev TODO" },
    },
    opts = {
        keywords = {
            WAIT = { icon = "⏳", color = "warning" },
            HOLD = { icon = "🛑", color = "error" },
        },
    },
}
