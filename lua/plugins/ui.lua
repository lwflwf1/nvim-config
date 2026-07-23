return {
    {
        "nvim-tree/nvim-web-devicons",
        lazy = true,
        opts = {},
    },
    {
        "olimorris/onedarkpro.nvim",
        name = "onedarkpro",
        lazy = false,
        priority = 1001,
        opts = {},
        config = function()
            pcall(vim.cmd.colorscheme, "onedark_vivid")
        end,
    },
    {
        "sainnhe/everforest",
        name = "everforest",
        lazy = true,
        priority = 1000,
        opts = {
            background = "hard",
            transparent_background = false,
        },
        init = function()
            vim.g.everforest_enable_italic = true
            vim.g.everforest_disable_italic_comment = false
        end,
    },
    {
        "catppuccin/nvim",
        name = "catppuccin",
        lazy = true,
        priority = 1000,
        opts = {
            flavour = "mocha",
            transparent_background = false,
            term_colors = true,
            integrations = {
                telescope = true,
                lualine = true,
                indent_blankline = false,
                gitsigns = true,
                which_key = true,
                nvimtree = false,
            },
        },
        config = function(_, opts)
            require("catppuccin").setup(opts)
        end,
    },
    {
        "nvim-lualine/lualine.nvim",
        event = "VeryLazy",
        dependencies = { "nvim-tree/nvim-web-devicons" },
        opts = {
            options = {
                theme = "auto",
                component_separators = { left = "|", right = "|" },
                section_separators = { left = "", right = "" },
                disabled_filetypes = {
                    statusline = { "help", "qf" },
                },
                always_divide_middle = true,
                globalstatus = true,
            },
            sections = {
                lualine_a = { { "mode", separator = { left = "" }, right_padding = 2 } },
                lualine_b = { "branch", "diff" },
                lualine_c = { { "filename", path = 1 }, "diagnostics" },
                lualine_x = {
                    { "filetype", padding = { left = 1, right = 1 } },
                    {
                        function()
                            local ff = vim.bo.fileformat
                            return ff == "dos" and "CRLF" or "LF"
                        end,
                        padding = { left = 1, right = 1 },
                    },
                },
                lualine_y = {},
                lualine_z = {
                    {
                        function()
                            local line = vim.fn.line(".")
                            local total = vim.fn.line("$")
                            local col = vim.fn.virtcol(".")
                            return string.format("%d/%d:%d", line, total, col)
                        end,
                        separator = { right = "" },
                        left_padding = 2,
                    },
                },
            },
            inactive_sections = {
                lualine_a = {},
                lualine_b = {},
                lualine_c = { "filename" },
                lualine_x = {},
                lualine_y = {},
                lualine_z = {},
            },
            tabline = {},
            extensions = {},
        },
    },
    {
        "akinsho/bufferline.nvim",
        event = "VeryLazy",
        dependencies = { "nvim-tree/nvim-web-devicons" },
        keys = {
            { "<leader>1", "<cmd>BufferLineGoToBuffer 1<CR>", desc = "Buffer 1" },
            { "<leader>2", "<cmd>BufferLineGoToBuffer 2<CR>", desc = "Buffer 2" },
            { "<leader>3", "<cmd>BufferLineGoToBuffer 3<CR>", desc = "Buffer 3" },
            { "<leader>4", "<cmd>BufferLineGoToBuffer 4<CR>", desc = "Buffer 4" },
            { "<leader>5", "<cmd>BufferLineGoToBuffer 5<CR>", desc = "Buffer 5" },
            { "<leader>6", "<cmd>BufferLineGoToBuffer 6<CR>", desc = "Buffer 6" },
            { "<leader>7", "<cmd>BufferLineGoToBuffer 7<CR>", desc = "Buffer 7" },
            { "<leader>8", "<cmd>BufferLineGoToBuffer 8<CR>", desc = "Buffer 8" },
            { "<leader>9", "<cmd>BufferLineGoToBuffer 9<CR>", desc = "Buffer 9" },
            { "<leader>bn", "<cmd>BufferLineMoveNext<CR>", desc = "Move buf next" },
            { "<leader>bp", "<cmd>BufferLineMovePrev<CR>", desc = "Move buf prev" },
            { "<leader>bb", "<cmd>BufferLinePick<CR>", desc = "Pick buffer" },
            { "<leader>bl", "<cmd>BufferLineCloseLeft<CR>", desc = "Close left" },
            { "<leader>br", "<cmd>BufferLineCloseRight<CR>", desc = "Close right" },
        },
        opts = {
            options = {
                mode = "buffers_and_tabs",
                numbers = "none",
                diagnostics = "nvim_lsp",
                offsets = { { filetype = "oil", text = "File Explorer", highlight = "Directory" } },
                indicator = { style = "icon", icon = "▎" },
                buffer_close_icon = "x",
                modified_icon = "*",
                close_icon = "x",
                left_trunc_marker = "...",
                right_trunc_marker = "...",
                max_name_length = 18,
                max_prefix_length = 15,
                tab_size = 18,
                show_buffer_close_icons = true,
                get_element_icon = function(e)
                    local ok, devicons = pcall(require, "nvim-web-devicons")
                    if ok then
                        return devicons.get_icon_by_filetype(e.filetype, { default = false })
                    end
                    return "[]"
                end,
                show_tab_indicators = true,
                persist_buffer_sort = true,
                separator_style = "thin",
                enforce_regular_tabs = false,
                always_show_bufferline = true,
                sort_by = "id",
            },
        },
    },

}
