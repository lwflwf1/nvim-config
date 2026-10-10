-- Mode component: just a glyph table keyed by vim.fn.mode(). The per-mode
-- color comes from the lualine theme preset (see the theme function below,
-- which moves each mode's a-section color from bg to fg).
local mode_icons = {
    n = "",
    i = "󰞇",
    v = "",
    V = "",
    ["\22"] = "",
    R = "󰈸",
    c = "",
    t = "",
    s = "",
    S = "",
    ["\19"] = "",
    no = "",
    ic = "",
    ix = "",
    Rv = "",
    cv = "",
    cr = "",
}

local function group_fg(name)
    local fg = vim.api.nvim_get_hl(0, { name = name }).fg
    return fg and { fg = ("#%06x"):format(fg) } or {}
end

local battery = require("box.battery")

local function mode_component()
    return mode_icons[vim.fn.mode()] or vim.fn.mode()
end

local function in_visual_select()
    return vim.tbl_contains({ "v", "V", "\22", "s", "S", "\19" }, vim.fn.mode(true))
end

-- Auto-cwd indicator: yellow while auto, Comment tint when pinned manually.
local function cwd_color()
    return group_fg(require("box.project").auto_enabled() and "DiagnosticWarn" or "Comment")
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

-- 'fileformat' only, no buffer scan. Under fileformats=unix (core/options.lua)
-- CRLF files read as LF with visible ^M, which <leader>ue / the click strips.
local function eol_label()
    return vim.bo.fileformat == "dos" and "CRLF" or "LF"
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
        "catppuccin/nvim",
        name = "catppuccin",
        -- not lazy: the colorscheme picker (<leader>uC) needs it on the rtp
        lazy = false,
        priority = 1000,
        opts = {}, -- defaults: flavour "auto" (mocha on dark)
    },
    {
        "rebelot/kanagawa.nvim",
        name = "kanagawa",
        -- not lazy: the colorscheme picker (<leader>uC) needs it on the rtp
        lazy = false,
        priority = 1000,
        opts = {},
    },
    {
        "AlexvZyl/nordic.nvim",
        name = "nordic",
        -- not lazy: the colorscheme picker (<leader>uC) needs it on the rtp
        lazy = false,
        priority = 1000,
        opts = {},
    },
    {
        "rmehri01/onenord.nvim",
        name = "onenord",
        -- not lazy: the colorscheme picker (<leader>uC) needs it on the rtp
        -- (two schemes: `onenord` dark / `onenord-light`)
        -- no opts: setup() force-applies the theme, which would hijack startup;
        -- `colorscheme onenord` loads the colors file directly
        lazy = false,
        priority = 1000,
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
                defaults.highlights.fill.bg = defaults.highlights.background.bg
                return defaults.highlights
            end,
            options = {
                hover = {
                    enabled = true,
                    delay = 200,
                    reveal = {'close'}
                },
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
                theme = require("box.theme").theme_unified,
                component_separators = { left = "", right = "" },
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
                        right_padding = 2,
                    },
                },
                lualine_b = {
                    { "branch", icon = "", on_click = branch_click },
                    { "diff", colored = true, symbols = { added = " ", modified = " ", removed = " " }, on_click = diff_click },
                },
                lualine_c = {
                    {
                        function ()
                            local session = require("box.sessions")
                            local name = session.name()
                            local kind = session.kind()
                            if kind == nil then return "󱙀" end
                            if kind == "local" then return "󱘻" end
                            if kind == "global" then return "󰪩 "..name end
                        end,
                        padding = { left = 1, right = 1 },
                        color = function ()
                            if require("box.sessions").active() then
                                return group_fg("DiagnosticOk")
                            else
                                return group_fg("Comment")
                            end
                        end,
                        on_click = function (_, button)
                            if button == "l" then
                                require("box.sessions").save()
                            else
                                require("box.sessions").pick_read()
                            end
                        end
                    },
                    {
                        function()
                            return vim.fn.fnamemodify(vim.fn.getcwd(), ":~")
                        end,
                        icon = "",
                        color = cwd_color,
                        padding = { left = 1, right = 1 },
                        on_click = function (_, button)
                            if button == "r" then
                                require("box.project").toggle_cwd()
                            elseif button == "l" then
                                -- same as <leader>pp
                                require("box.project").pick()
                            end
                        end,
                    },
                    { "filetype", icon_only = true, padding = { left = 0, right = 0 } },
                    { "filename", path = 1, padding = { left = 0, right = 1 }, symbols = {
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
                        padding = { left = 0, right = 1 },
                        on_click = function() vim.cmd("Trouble diagnostics toggle") end,
                    },
                },
                lualine_x = {
                    {
                        function()
                            local reg = vim.fn.reg_recording()
                            return reg ~= "" and ("@" .. reg) or ""
                        end,
                        icon = "󰑋",
                        padding = { left = 1, right = 0 },
                        color = function() return group_fg("DiagnosticError") end,
                        on_click = function()
                            if vim.fn.reg_recording() ~= "" then
                                vim.api.nvim_feedkeys("q", "n", false)
                            end
                        end,
                    },
                    {
                        eol_label,
                        padding = { left = 1, right = 0 },
                        color = function() return group_fg("Operator") end,
                        -- same action as <leader>ue
                        on_click = function() require("box.trim").trim_trailing() end,
                    },
                    {   "filetype",
                        padding = { left = 1, right = 1 },
                        on_click = function(_, button)
                            if button == "l" then
                                vim.ui.select(vim.fn.getcompletion("", "filetype"), { prompt = "Filetype" }, function(choice)
                                    if choice then
                                        vim.bo.filetype = choice
                                    end
                                end)
                            else
                                require("box.lsp").pick_config({ attached = 0 })
                            end
                        end
                    },
                },
                lualine_y = {},
                lualine_z = {
                    {
                        "selectioncount",
                        left_padding = 2,
                        color = function() return group_fg("Keyword") end,
                        cond = in_visual_select,
                        icon = "",
                    },
                    {
                        function()
                            local line = vim.fn.line(".")
                            local total = vim.fn.line("$")
                            local col = vim.fn.virtcol(".")
                            return string.format("%d/%d:%d", line, total, col)
                        end,
                        icon = "",
                        left_padding = 2,
                        color = function() return group_fg("Keyword") end,
                        cond = function() return not in_visual_select() end,
                    },
                    {
                        function()
                            if not battery.pct then return "" end
                            return battery.get_icon() .. " " .. battery.get() .. "%%"
                        end,
                        color = function()
                            if battery.charging or battery.pct and battery.pct >= 50 then return group_fg("DiagnosticOk")
                            elseif battery.pct and battery.pct >= 20 then return group_fg("DiagnosticWarn")
                            else return group_fg("DiagnosticError") end
                        end,
                        padding = { left = 1, right = 1 },
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
                -- default places confirm at row 3; keep it centered instead
                confirm = {
                    position = { row = "50%", col = "50%" },
                },
                -- solid = space-filled border: reads as a padding ring around the
                -- cmdline, filled with the float bg (border bg falls back to Normal)
                cmdline_popup = {
                    border = { style = "solid", padding = { 0, 0 } },
                    win_options = { winhighlight = { Normal = "NormalFloat" } },
                },
                -- only shown for native completions (blink draws its own menu)
                cmdline_popupmenu = {
                    border = { style = "solid", padding = { 0, 0 } },
                    win_options = { winhighlight = { Normal = "NormalFloat" } },
                },
            },
            lsp = {
                override = {
                    ["vim.lsp.util.convert_input_to_markdown_lines"] = true,
                    ["vim.lsp.util.stylize_markdown"] = true,
                },
            },
            presets = {
                -- cmdline popup at top center; blink's menu stacks below it (it
                -- anchors to noice's ui_cmdline_pos)
                command_palette = true,
                long_message_to_split = true,
            },
        },
    },
}
