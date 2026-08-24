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
                    {
                        function()
                            return vim.fn.pathshorten(vim.fn.fnamemodify(vim.fn.getcwd(), ":~"))
                        end,
                        padding = { left = 1, right = 1 },
                    },
                },
                lualine_c = {
                    { "filename", path = 1, symbols = {
                        modified = " ",
                        readonly = "",
                        unnamed  = "[No Name]",
                        newfile  = "[New]",
                    } },
                    "diagnostics",
                },
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
            -- Bufferline derives its colors by darkening the colorscheme's
            -- Normal bg by 25-45%, which collapses to near-black on dark
            -- themes (onedark_vivid #282c34). On dark themes, re-shade with
            -- gentle factors (fill < bar < selected) so the tabline stays a
            -- distinct, statusline-like strip instead of black edges. Light
            -- themes keep bufferline's own shading, which reads fine there.
            -- Note: bufferline passes the FULL defaults table (options +
            -- highlights map) to the function.
            highlights = function(defaults)
                local ok, norm = pcall(vim.api.nvim_get_hl_by_name, "Normal", true)
                if not ok or not norm.background then
                    return {}
                end
                local bg = ("#%06x"):format(norm.background)
                local r = tonumber(bg:sub(2, 3), 16)
                local g = tonumber(bg:sub(4, 5), 16)
                local b = tonumber(bg:sub(6, 7), 16)
                local luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255
                if luminance > 0.5 then
                    return {}
                end
                local function shade(hex, pct)
                    local f = (100 + pct) / 100
                    local rr = tonumber(hex:sub(2, 3), 16)
                    local gg = tonumber(hex:sub(4, 5), 16)
                    local bb = tonumber(hex:sub(6, 7), 16)
                    return ("#%02x%02x%02x"):format(math.floor(rr * f), math.floor(gg * f), math.floor(bb * f))
                end
                local fill_bg = shade(bg, -30)
                local bar_bg = shade(bg, -22)
                local vis_bg = shade(bg, -14)
                local out = {}
                for g, d in pairs(defaults.highlights) do
                    if d and type(d) == "table" then
                        local tier = bar_bg
                        if g == "fill" then
                            tier = fill_bg
                        elseif g:match("_selected$") then
                            tier = bg
                        elseif g:match("_visible$") then
                            tier = vis_bg
                        end
                        local o = { bg = tier }
                        if d.fg then o.fg = d.fg end
                        if d.bold then o.bold = true end
                        if d.italic then o.italic = true end
                        if d.underline then o.underline = true end
                        if d.sp then o.sp = d.sp end
                        out[g] = o
                    end
                end
                return out
            end,
            options = {
                mode = "buffers_and_tabs",
                numbers = "none",
                diagnostics = "nvim_lsp",
                offsets = { { filetype = "oil", text = "File Explorer", highlight = "Directory" } },
                indicator = { style = "icon", icon = "▎" },
                buffer_close_icon = "",
                modified_icon = "",
                close_icon = "",
                left_trunc_marker = "...",
                right_trunc_marker = "...",
                max_name_length = 40,
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
        opts = {
            views = {
                confirm = {
                    backend = "popup",
                    position = { row = "50%", col = "50%" },
                },
            },
            cmdline = {
                view = "cmdline",
                opts = {
                    zindex = 200,
                },
            },
            lsp = {
                override = {
                    ["vim.lsp.util.convert_input_to_markdown_lines"] = true,
                    ["vim.lsp.util.stylize_markdown"] = true,
                },
            },
            presets = {
                bottom_search = true,
                long_message_to_split = true,
                inc_rename = false,
                lsp_doc_border = false,
            },
        },
    },
}
