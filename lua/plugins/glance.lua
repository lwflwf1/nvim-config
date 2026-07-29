return {
    {
        "dnlhc/glance.nvim",
        cmd = "Glance",
        keys = {
            { "<leader>ld", "<cmd>Glance definitions<CR>", desc = "Glance definitions" },
            { "<leader>lr", "<cmd>Glance references<CR>", desc = "Glance references" },
            { "<leader>lt", "<cmd>Glance type_definitions<CR>", desc = "Glance type definitions" },
            { "<leader>li", "<cmd>Glance implementations<CR>", desc = "Glance implementations" },
        },
        opts = function()
            local actions = require("glance").actions
            return {
                height = 18,
                zindex = 45,

                preview_win_opts = {
                    cursorline = true,
                    number = true,
                    wrap = false,
                },

                border = {
                    enable = false,
                    top_char = "―",
                    bottom_char = "―",
                },

                list = {
                    position = "left",
                    width = 0.33,
                },

                theme = {
                    enable = true,
                    mode = "auto",
                },

                mappings = {
                    list = {
                        ["j"] = actions.next,
                        ["k"] = actions.previous,
                        ["<Down>"] = actions.next,
                        ["<Up>"] = actions.previous,
                        ["<Tab>"] = actions.next_location,
                        ["<S-Tab>"] = actions.previous_location,
                        ["<C-u>"] = actions.preview_scroll_win(5),
                        ["<C-d>"] = actions.preview_scroll_win(-5),
                        ["v"] = actions.jump_vsplit,
                        ["s"] = actions.jump_split,
                        ["t"] = actions.jump_tab,
                        ["<CR>"] = actions.jump,
                        ["o"] = actions.jump,
                        ["l"] = actions.open_fold,
                        ["h"] = actions.close_fold,
                        ["<leader>l"] = actions.enter_win("preview"),
                        ["q"] = actions.close,
                        ["Q"] = actions.close,
                        ["<Esc>"] = actions.close,
                    },
                    preview = {
                        ["Q"] = actions.close,
                        ["<Tab>"] = actions.next_location,
                        ["<S-Tab>"] = actions.previous_location,
                        ["<leader>l"] = actions.enter_win("list"),
                    },
                },

                hooks = {},
                folds = {
                    fold_closed = "",
                    fold_open = "",
                    folded = true,
                },

                indent_lines = {
                    enable = true,
                    icon = "│",
                },

                winbar = {
                    enable = true,
                },
            }
        end,
    },
}
