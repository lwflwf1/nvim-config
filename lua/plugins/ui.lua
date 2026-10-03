-- Mode component: just a glyph table keyed by vim.fn.mode(). The per-mode
-- color comes from the lualine theme preset (see the theme function below,
-- which moves each mode's a-section color from bg to fg).
local mode_icons = {
    n = "",
    i = "",
    v = "",
    V = "",
    ["\22"] = "",
    R = "",
    c = "",
    t = "",
    s = "",
    S = "",
    ["\19"] = "",
    no = "",
    ic = "",
    ix = "",
    Rv = "",
    cv = "",
    cr = "",
}

local function group_fg(name)
    local fg = vim.api.nvim_get_hl(0, { name = name }).fg
    return fg and { fg = ("#%06x"):format(fg) } or {}
end

local function mode_component()
    return mode_icons[vim.fn.mode()] or vim.fn.mode()
end

local function in_visual_select()
    return vim.tbl_contains({ "v", "V", "\22", "s", "S", "\19" }, vim.fn.mode(true))
end

-- Auto-cwd indicator: yellow while auto, Comment tint when pinned manually.
local function cwd_color()
    return group_fg(vim.g.auto_cwd == false and "Comment" or "DiagnosticWarn")
end

local function toggle_auto_cwd()
    require("core.keymaps").toggle_auto_cwd()
    require("lualine").refresh()
end

local function branch_click()
    vim.cmd("Neogit")
end

local function diff_click(_, button)
    local file = vim.fn.expand("%:.")
    if file == "" then return end
    file = vim.fn.fnameescape(file)
    if button == "r" then
        vim.cmd("DiffviewFileHistory " .. file)
    else
        vim.cmd("DiffviewOpen -- " .. file)
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
                ["@punctuation.bracket"] = { link = "Constant" }, -- all brackets take the theme's Constant color (SV has no lang-specific group, so it needs the generic one)
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
            -- colorscheme is applied centrally by config/theme.lua (single source of truth for the default)
        end,
    },
    {
        "sainnhe/everforest",
        name = "everforest",
        -- not lazy: the colorscheme picker (<leader>uC) needs it on the rtp;
        -- no Lua module, so it must not get opts (lazy would auto-require and
        -- error on setup)
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
                    -- Every section shares the editor background (Normal). With
                    -- kitty's transparent_background_colors the cells carry the
                    -- exact Normal hex, so they get the same transparency
                    -- treatment as the editor body. Each mode's a-section color
                    -- from the preset (green/blue/purple/...) is moved from bg
                    -- to fg, so the mode icon keeps lualine's per-mode colors
                    -- on the unified editor background.
                    local normal = vim.api.nvim_get_hl(0, { name = "Normal" })
                    if not normal.bg then
                        return theme
                    end
                    local bg = ("#%06x"):format(normal.bg)
                    local fg = normal.fg and ("#%06x"):format(normal.fg) or nil
                    for mode, sections in pairs(theme) do
                        if mode ~= "inactive" and type(sections) == "table" then
                            local accent = type(sections.a) == "table" and sections.a.bg or nil
                            for _, section in pairs(sections) do
                                if type(section) == "table" then
                                    section.bg = bg
                                end
                            end
                            if type(sections.a) == "table" then
                                sections.a.fg = accent or fg
                            end
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
                    {
                        mode_component,
                        separator = { left = "" },
                        right_padding = 2,
                    },
                    -- Macro recording indicator. noice suppresses the native
                    -- "recording @a" msg_showmode message and lualine's mode
                    -- component can't distinguish recording from insert/visual,
                    -- so show only while recording via reg_recording().
                    -- Left-click stops the recording.
                    {
                        function() return vim.fn.reg_recording() end,
                        cond = function() return vim.fn.reg_recording() ~= "" end,
                        fmt = function(reg) return "REC @" .. reg end,
                        padding = { left = 1, right = 1 },
                        on_click = function()
                            if vim.fn.reg_recording() ~= "" then
                                vim.api.nvim_feedkeys("q", "n", false)
                            end
                        end,
                    },
                },
                lualine_b = {
                    { "branch", icon = "", separator = { right = "" }, on_click = branch_click },
                    { "diff", colored = true, symbols = { added = " ", modified = " ", removed = " " }, on_click = diff_click },
                },
                lualine_c = {
                    {
                        function()
                            return "󰋜 "..vim.fn.fnamemodify(vim.fn.getcwd(), ":~")
                        end,
                        separator = "",
                        color = cwd_color,
                        padding = { left = 1, right = 1 },
                        on_click = toggle_auto_cwd,
                    },
                    { "filetype", icon_only = true, separator = "", padding = { left = 0, right = 0 } },
                    { "filename", path = 1, separator = "", padding = { left = 0, right = 1 }, symbols = {
                        modified = " ",
                        readonly = "",
                        unnamed  = "[No Name]",
                        newfile  = "[New]",
                    }, on_click = function(_, button)
                        if button == "r" then
                            local path = vim.fn.expand("%:p")
                            if path == "" then return end
                            local ok = pcall(vim.fn.setreg, "+", path)
                            vim.notify(ok and ("Copied: " .. path) or "Clipboard unavailable",
                                ok and vim.log.levels.INFO or vim.log.levels.WARN)
                        else
                            require("snacks").picker.files()
                        end
                    end },
                    {
                        "diagnostics",
                        separator = "",
                        padding = { left = 0, right = 1 },
                        on_click = function() vim.cmd("Trouble diagnostics toggle") end,
                    },
                },
                lualine_x = {
                    {
                        function()
                            local ff = vim.bo.fileformat
                            return ff == "dos" and "CRLF" or "LF"
                        end,
                        padding = { left = 1, right = 1 },
                        separator = "",
                        color = "Operator",
                        on_click = function()
                            vim.bo.fileformat = vim.bo.fileformat == "dos" and "unix" or "dos"
                            vim.notify("fileformat: " .. vim.bo.fileformat, vim.log.levels.INFO)
                            require("lualine").refresh()
                        end,
                    },
                    { "lsp_status", icon = "{}", separator = "", padding = { left = 1, right = 1 }, color = function() return group_fg("String") end },
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
                        "selectioncount",
                        separator = { right = "" },
                        left_padding = 2,
                        color = function() return group_fg("Keyword") end,
                        cond = in_visual_select,
                    },
                    {
                        function()
                            local line = vim.fn.line(".")
                            local total = vim.fn.line("$")
                            local col = vim.fn.virtcol(".")
                            return string.format("%d/%d:%d", line, total, col)
                        end,
                        separator = { right = "" },
                        left_padding = 2,
                        color = function() return group_fg("Keyword") end,
                        cond = function() return not in_visual_select() end,
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
