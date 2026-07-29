return {
    {
        "stevearc/aerial.nvim",
        cmd = { "AerialToggle", "AerialOpen", "AerialNavToggle" },
        dependencies = {
            "echasnovski/mini.nvim",
            "ibhagwan/fzf-lua",
        },
        keys = {
            { "<leader>lo", "<cmd>AerialToggle!<CR>", desc = "Aerial outline" },
            { "<leader>lO", "<cmd>AerialNavToggle<CR>", desc = "Aerial nav window" },
            { "<leader>fs", function() require("aerial").fzf_lua_picker() end, desc = "Aerial symbols (fzf)" },
            { "]s", function() require("aerial").next() end, desc = "Next symbol" },
            { "[s", function() require("aerial").prev() end, desc = "Prev symbol" },
        },
        opts = {
            attach_mode = "global",
            manage_folds = true,
            link_folds_to_tree = true,
            link_tree_to_folds = true,
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
