return {
    "folke/todo-comments.nvim",
    event = "VeryLazy",
    dependencies = { "nvim-lua/plenary.nvim" },
    keys = {
        { "<leader>tl", "<cmd>Trouble todo toggle<CR>", desc = "TODOs to trouble" },
        { "<leader>]o", "<cmd>lua require('todo-comments').jump_next()<CR>", desc = "Next TODO" },
        { "<leader>[o", "<cmd>lua require('todo-comments').jump_prev()<CR>", desc = "Prev TODO" },
    },
}
