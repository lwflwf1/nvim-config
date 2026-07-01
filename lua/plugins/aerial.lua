return {
    {
        "stevearc/aerial.nvim",
        cmd = { "AerialToggle", "AerialOpen", "AerialNavToggle" },
        dependencies = {
            "nvim-tree/nvim-web-devicons",
        },
        keys = {
            { "<leader>l", "<cmd>AerialToggle!<CR>", desc = "Aerial outline" },
        },
        opts = {
            backends = { "treesitter", "lsp", "markdown" },
            layout = {
                default_direction = "prefer_right",
                max_width = { 40, 0.2 },
                min_width = 10,
            },
            filter_kind = {
                "Class",
                "Constructor",
                "Enum",
                "Function",
                "Interface",
                "Module",
                "Method",
                "Struct",
                "Variable",
                "Property",
            },
            show_guides = true,
            on_attach = function(bufnr)
                vim.keymap.set("n", "{", "<cmd>AerialPrev<CR>", { buffer = bufnr, desc = "Previous symbol" })
                vim.keymap.set("n", "}", "<cmd>AerialNext<CR>", { buffer = bufnr, desc = "Next symbol" })
            end,
        },
    },
}
