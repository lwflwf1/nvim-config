return {
    {
        "olimorris/onedarkpro.nvim",
        name = "onedarkpro",
        lazy = false,
        priority = 1001,
        opts = {
            highlights = {
                ["@punctuation.bracket"] = { fg = "#61afef" }, -- brackets same color as function call (blue)
            },
        },
        config = function(_, opts)
            require("onedarkpro").setup(opts)
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
                lualine_b = {
                    { "branch", icon = "" },
                    { "diff", colored = true, symbols = { added = " ", modified = " ", removed = " " } },
                },
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
                    -- {
                    --     function() return require("noice").api.status.command.get() end,
                    --     cond = function() return package.loaded["noice"] and require("noice").api.status.command.has() end,
                    -- },
                    -- {
                    --     function() return require("noice").api.status.mode.get() end,
                    --     cond = function() return package.loaded["noice"] and require("noice").api.status.mode.has() end,
                    -- },
                    -- {
                    --     function() return require("noice").api.status.search.get() end,
                    --     cond = function() return package.loaded["noice"] and require("noice").api.status.search.has() end,
                    -- },
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
                        return devicons.get_icon_by_filetype(e.filetype)
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
    {
        "folke/noice.nvim",
        event = "VeryLazy",
        dependencies = {
            "MunifTanjim/nui.nvim",
        },
        require("noice").setup({
            views = {
                confirm = {
                    backend = "popup",
                    position = { row = "50%", col = "50%" },
                },
            },
            cmdline = {
                view = "cmdline",
            },
            lsp = {
                -- override markdown rendering so that **cmp** and other plugins use **Treesitter**
                override = {
                    ["vim.lsp.util.convert_input_to_markdown_lines"] = true,
                    ["vim.lsp.util.stylize_markdown"] = true,
                    ["cmp.entry.get_documentation"] = true, -- requires hrsh7th/nvim-cmp
                },
            },
            -- you can enable a preset for easier configuration
            presets = {
                bottom_search = true, -- use a classic bottom cmdline for search
                command_palette = true, -- position the cmdline and popupmenu together
                long_message_to_split = true, -- long messages will be sent to a split
                inc_rename = false, -- enables an input dialog for inc-rename.nvim
                lsp_doc_border = false, -- add a border to hover docs and signature help
            },
        })
    },
}
