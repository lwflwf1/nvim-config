return {
    {
        "goolord/alpha-nvim",
        lazy = false,
        priority = 999,
        dependencies = { "nvim-lua/plenary.nvim" },
        config = function()
            local alpha = require("alpha")
            local theme = require("alpha.themes.dashboard")

            theme.section.header.val = {
                "                                                     ",
                "  ███╗   ██╗███████╗ ██████╗ ██╗   ██╗██╗███╗   ███╗ ",
                "  ████╗  ██║██╔════╝██╔═══██╗██║   ██║██║████╗ ████║ ",
                "  ██╔██╗ ██║█████╗  ██║   ██║██║   ██║██║██╔████╔██║ ",
                "  ██║╚██╗██║██╔══╝  ██║   ██║╚██╗ ██╔╝██║██║╚██╔╝██║ ",
                "  ██║ ╚████║███████╗╚██████╔╝ ╚████╔╝ ██║██║ ╚═╝ ██║ ",
                "  ╚═╝  ╚═══╝╚══════╝ ╚═════╝   ╚═══╝  ╚═╝╚═╝     ╚═╝ ",
                "                                                     ",
            }
            theme.section.header.opts.hl = "Title"

            theme.section.buttons.val = {
                theme.button("f", "    Find file", ":Telescope find_files<CR>"),
                theme.button("r", "    Recent files", ":Telescope oldfiles<CR>"),
                theme.button("g", "    Live grep", ":Telescope live_grep<CR>"),
                theme.button("b", "    Buffers", ":Telescope buffers<CR>"),
                theme.button("e", "    File tree", ":NvimTreeToggle<CR>"),
                theme.button("q", "    Quit", ":qa<CR>"),
            }

            theme.section.footer.val = {}

            alpha.setup(theme.config)

            vim.api.nvim_create_autocmd("User", {
                pattern = "LazyVimStarted",
                callback = function()
                    local stats = require("lazy").stats()
                    local ms = math.floor(stats.startuptime * 100 + 0.5) / 100
                    local line = "    Loaded " .. stats.count .. " plugins in " .. ms .. "ms"
                    theme.section.header.val[8] = line
                    pcall(alpha.redraw)
                end,
            })
        end,
    },
}
