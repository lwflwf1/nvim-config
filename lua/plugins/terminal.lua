return {
    {
        "akinsho/toggleterm.nvim",
        cmd = { "ToggleTerm", "ToggleTermToggleAll", "TermExec" },
        keys = {
            { "<M-=>", "<cmd>ToggleTerm<CR>", desc = "Toggle terminal" },
            { "<M-+>", "<cmd>ToggleTerm direction=horizontal<CR>", desc = "New terminal" },
            { "<M-->", "<cmd>ToggleTermToggleAll<CR>", desc = "Kill terminal" },
        },
        opts = {
            size = 15,
            open_mapping = [[<M-=>]],
            hide_numbers = true,
            shade_filetypes = {},
            shade_terminals = true,
            shading_factor = 2,
            start_in_insert = true,
            insert_mappings = true,
            persist_size = true,
            direction = "float",
            float_opts = {
                border = "curved",
                winblend = 3,
                highlights = {
                    border = "Normal",
                    background = "Normal",
                },
            },
        },
    },
}
