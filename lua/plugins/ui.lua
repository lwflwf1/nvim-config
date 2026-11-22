-- Mode component: just a glyph table keyed by vim.fn.mode(). The per-mode
-- color comes from the lualine theme preset (see the theme function below,
-- which moves each mode's a-section color from bg to fg).
-- local mode_icons = {
--     n = "󱍀",
--     i = "",
--     v = "󰒅",
--     V = "󰜩",
--     ["\22"] = "󰕰",
--     R = "󰈸",
--     c = "",
--     t = "",
--     s = "",
--     S = "",
--     ["\19"] = "",
--     no = "",
--     ic = "",
--     ix = "",
--     Rv = "",
--     cv = "",
--     cr = "",
-- }

local function group_fg(name)
    local fg = vim.api.nvim_get_hl(0, { name = name }).fg
    return fg and { fg = ("#%06x"):format(fg) } or {}
end

local battery = require("box.battery")

-- local function mode_component()
--     return mode_icons[vim.fn.mode()] or vim.fn.mode()
-- end

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
                -- everything the colorscheme is *missing* (BlinkCmpKind*,
                -- GitSignsStaged*, Aerial*, DropBar*Task)
                -- lives in lua/box/hl.lua, not here: those are re-applied on
                -- ColorScheme so a `hi clear` can't drop them.
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
        opts = function()
            -- Register blade2049 HERE, and the placement is load-bearing.
            -- `catppuccin/init.lua` validates `flavour` against a hardcoded
            -- `M.flavours = {latte, frappe, macchiato, mocha}` and notifies an
            -- error for anything else, so the entry must exist before
            -- `setup()` -- and `setup()` only recompiles what it finds in
            -- `M.flavours`.
            --
            -- This function is the one place that is both guaranteed late
            -- enough to have catppuccin on the rtp and guaranteed early enough
            -- to be before setup(): lazy evaluates `opts` as an argument of
            -- `require(main).setup(opts)` (lazy/core/loader.lua, `M.config`),
            -- after `packadd`. The two alternatives are both wrong here:
            --   * module scope -- `require("catppuccin")` fails, the plugin is
            --     not on the rtp yet, and the whole spec file fails to import.
            --   * the `init` hook -- measured, not assumed: a cold-cache
            --     `setup()` recompiled the four official flavours and skipped
            --     blade2049, then `M.compile()` wrote `cached` anyway, so the
            --     stale colours survived every later start with no error
            --     anywhere. `M.compile()` also swallows a failure to compile a
            --     flavour (`compiler.lua:74-92` prints and returns), so a miss
            --     is invisible by construction.
            require("catppuccin").flavours.blade2049 = 5

            -- keyed by flavour, so plain `catppuccin` (auto -> mocha) is
            -- untouched and the film theme stays one `:colorscheme` away.
            -- The palette itself cannot come from here: catppuccin resolves it
            -- by filename (see lua/catppuccin/palettes/blade2049.lua).
            --
            -- `overrides` is applied to OUR palette eagerly, not handed over as
            -- a function, for two reasons (both verified):
            --  * lib/hashing.lua:17 hashes a function as `fn(get_palette())`,
            --    and at setup() time get_palette() returns *mocha's* palette --
            --    so a change to any of OUR hexes would not invalidate the
            --    compiled cache and the theme would silently keep the old
            --    colours. A plain table hashes what it actually contains.
            --  * lib/mapper.lua:64 replaces a function entry with its result,
            --    mutating the options table for the rest of the session.
            local b = require("box.colors.blade2049")
            return {
                highlight_overrides = { blade2049 = b.overrides(b.palette) },
            }
        end,
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
                        -- mode_component,
                        function () return "" end,
                        right_padding = 1,
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
                            require("box.path").copy()
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
                        function ()
                            local prefix = require("box.sticky").status()
                            return prefix ~= "" and "Sticky: "..prefix or ""
                        end,
                        color = function() return group_fg("DiagnosticError") end,
                    },
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
            -- The wakatime plugin reports a failed heartbeat through vim.notify.
            -- On this air-gapped box that failure is permanent and expected --
            -- api_url is the 127.0.0.1:1 placeholder, so wakatime-cli can never
            -- validate the api key -- and it recurs once per heartbeat_rate_limit
            -- window for as long as the editor is open. Routing it out through
            -- noice's own `skip` filter is what the plugin documents for this
            -- (doc/noice.nvim.txt ROUTES), and it is the same mechanism that
            -- drops the `recording @a` messages; wrapping vim.notify instead
            -- would fight whoever owns the notify handler. Gated on is_rhel6 so
            -- a networked box still sees genuine wakatime notifications.
            -- Noice is VeryLazy-loaded, so before that the message still echoes
            -- through the default handler once.
            routes = vim.g.is_rhel6 and {
                {
                    filter = { event = "notify", find = "%[WakaTime%]" },
                    opts = { skip = true },
                },
            } or {},
        },
        config = function(_, opts)
            require("noice").setup(opts)

            local function noice_scroll(delta, n_fallback, i_fallback)
                return function()
                    if not require("noice.lsp").scroll(delta) then
                        return vim.fn.mode() == "n" and n_fallback or i_fallback
                    end
                    return ""
                end
            end

            local map_opts = { silent = true, expr = true }
            vim.keymap.set({ "n", "i", "s" }, "<C-f>", noice_scroll(4, "<C-f>zz", "<Right>"), map_opts)
            vim.keymap.set({ "n", "i", "s" }, "<C-b>", noice_scroll(-4, "<C-b>zz", "<Left>"), map_opts)
            vim.keymap.set({ "n", "i", "s" }, "<C-d>", noice_scroll(4, "<C-d>zz", "<Del>"), map_opts)
            vim.keymap.set({ "n", "i", "s" }, "<C-u>", noice_scroll(-4, "<C-u>zz", "<C-u>"), map_opts)
        end,
    },
}
