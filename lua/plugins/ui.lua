local function hl_fg(name)
    return function()
        local fg = vim.api.nvim_get_hl(0, { name = name }).fg
        return fg and { fg = ("#%06x"):format(fg) } or {}
    end
end

return {
    {
        "olimorris/onedarkpro.nvim",
        name = "onedarkpro",
        lazy = false,
        priority = 1001,
        opts = {
            highlights = {
                CursorLine = { link = "ColorColumn" },
                FloatTitle = { fg = "${green}", bg = "${float_bg}" },
                ["@punctuation.bracket"] = { fg = "#d19a66" }, -- all brackets orange (SV has no lang-specific group, so it needs the generic one)
                -- blink.cmp and this theme both omit CmpItemKind*/BlinkCmpKind*
                -- for these 4 kinds; link them to the theme's own semantic
                -- groups so both the icon and the kind label stay colored.
                ["BlinkCmpKindVariable"] = { link = "Identifier" },
                ["BlinkCmpKindFolder"] = { link = "Directory" },
                ["BlinkCmpKindReference"] = { link = "Tag" },
                ["BlinkCmpKindColor"] = { link = "Constant" },
                -- onedarkpro also omits the label detail/description groups, so
                -- without use_nvim_cmp_as_default they'd fall back to PmenuExtra
                -- (no fg). Link them to the theme's own secondary-text group.
                ["BlinkCmpLabelDetail"] = { link = "BlinkCmpSource" },
                ["BlinkCmpLabelDescription"] = { link = "BlinkCmpSource" },
            },
        },
        config = function(_, opts)
            require("onedarkpro").setup(opts)
            -- colorscheme 由 config/theme.lua 统一应用（默认值的单一来源）
        end,
    },
    {
        "sainnhe/everforest",
        name = "everforest",
        -- 不 lazy：colorscheme picker（<leader>uC）需要它在 rtp 上；
        -- 无 lua 模块，不能带 opts（lazy 会自动 require(...).setup 而报错）
        lazy = false,
        priority = 1000,
        init = function()
            vim.g.everforest_enable_italic = true
            vim.g.everforest_disable_italic_comment = false
        end,
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
            highlights = function(defaults)
                defaults.highlights.fill.bg = defaults.highlights.buffer_selected.bg
                return defaults.highlights
            end,
            options = {
                mode = "buffers_and_tabs",
                numbers = "none",
                diagnostics = "nvim_lsp",
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
                separator_style = { "", "" },
                enforce_regular_tabs = false,
                always_show_bufferline = true,
                sort_by = "id",
            },
        },
        config = function(_, opts)
            require("bufferline").setup(opts)
            -- nvim normalises buffer names to forward slashes on Windows (even
            -- when opened with `\`), but bufferline derives its separator from
            -- `has("win32")` and splits on "\\" -> splitting the path fails, the
            -- duplicate detection bails at depth 1 and the parent-dir prefix
            -- collapses to a bare "\", so two buffers named `view.lua` both
            -- render as `\view.lua`. Split on "/" instead (a no-op on Linux).
            require("bufferline.utils").path_sep = "/"
        end,
    },
    {
        "nvim-lualine/lualine.nvim",
        event = "VeryLazy",
        dependencies = { "nvim-tree/nvim-web-devicons" },
        opts = {
            options = {
                theme = function()
                    local loader = require("lualine.utils.loader")
                    local ok, theme = pcall(loader.load_theme, "auto")
                    if not ok or type(theme) ~= "table" then
                        return "auto"
                    end
                    local b_bg = vim.api.nvim_get_hl(0, { name = "NormalFloat" }).bg
                    local c_bg = vim.api.nvim_get_hl(0, { name = "Normal" }).bg
                    for mode, sections in pairs(theme) do
                        if mode ~= "inactive" and type(sections) == "table" then
                            if sections.b and b_bg then sections.b.bg = ("#%06x"):format(b_bg) end
                            if sections.c and c_bg then sections.c.bg = ("#%06x"):format(c_bg) end
                        end
                    end
                    return theme
                end,
                component_separators = { left = "|", right = "|" },
                section_separators = { left = "", right = "" },
                disabled_filetypes = {
                    statusline = { "help", "qf" },
                },
                always_divide_middle = true,
                globalstatus = true,
            },
            sections = {
                lualine_a = {
                    { "mode", separator = { left = "" }, right_padding = 2 },
                    -- Macro recording indicator. noice suppresses the native
                    -- "recording @a" msg_showmode message and lualine's mode
                    -- component can't distinguish recording from insert/visual,
                    -- so show only while recording via reg_recording().
                    {
                        function() return vim.fn.reg_recording() end,
                        cond = function() return vim.fn.reg_recording() ~= "" end,
                        fmt = function(reg) return "REC @" .. reg end,
                        padding = { left = 1, right = 1 },
                    },
                },
                lualine_b = {
                    { "branch", icon = "", separator = { right = "" },},
                    { "diff", colored = true, symbols = { added = " ", modified = " ", removed = " " } },
                },
                lualine_c = {
                    {
                        function()
                            return " "..vim.fn.fnamemodify(vim.fn.getcwd(), ":~")
                        end,
                        separator = "",
                        color = hl_fg("Comment"),
                        padding = { left = 1, right = 1 },
                    },
                    { "filetype", icon_only = true, separator = "", padding = { left = 0, right = 0 } },
                    { "filename", path = 1, separator = "", padding = { left = 0, right = 1 }, symbols = {
                        modified = " ",
                        readonly = "",
                        unnamed  = "[No Name]",
                        newfile  = "[New]",
                    } },
                    { "diagnostics", separator = "", padding = { left = 0, right = 1 } },
                },
                lualine_x = {
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
        -- lualine does not refresh on recording start/stop by default.
        config = function(_, opts)
            require("lualine").setup(opts)
            vim.api.nvim_create_autocmd({ "RecordingEnter", "RecordingLeave" }, {
                callback = function() require("lualine").refresh() end,
            })
        end,
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
