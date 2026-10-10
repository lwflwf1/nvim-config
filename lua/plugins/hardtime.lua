return {
    "m4xshen/hardtime.nvim",
    dependencies = { "MunifTanjim/nui.nvim" },
    lazy = false,
    opts = {
        -- default 3 is harsh at the start; loosen now, tighten later if needed
        max_count = 5,
        restricted_keys = {
            -- <C-n>/<C-p> add multicursors (box/multicursor.lua); rapid repeats
            -- are the whole point of the feature, so never restrict them.
            ["<C-N>"] = false,
            ["<C-P>"] = false,
            -- j/k are globally remapped to the display-line gj/gk (core/keymaps.lua),
            -- so don't restrict the raw gj/gk either.
            ["gj"] = false,
            ["gk"] = false,
        },
        -- hardtime's default clears vim.o.mouse on every BufEnter, which would kill
        -- the lualine/bufferline on_click handlers and picker clicking.
        disable_mouse = false,
        disabled_filetypes = {
            -- snacks pickers/explorer are the whole find UI; j/k there is list/dir
            -- navigation, not editing (vim.ui.select = Snacks.picker.select,
            -- see snacks.lua), and the input handles arrows itself.
            snacks_picker_list = true,
            snacks_picker_input = true,
            snacks_picker_preview = true,
            snacks_input = true,
            snacks_terminal = true,
            snacks_notif = true,
            snacks_notif_history = true,
            snacks_win_help = true,
            snacks_win_backdrop = true,
            snacks_layout_box = true,
            -- list-like UIs navigated with j/k
            harpoon = true,
            ["grug-far"] = true,
            OverseerList = true,
            -- notes and scrolling-only buffers
            org = true,
            orgagenda = true,
            log = true,
            bigfile = true,
        },
    },
    config = function(_, opts)
        -- lazy only auto-calls setup() when `config` is absent, so call it here
        -- (same reason the onedarkpro spec calls its setup explicitly).
        require("hardtime").setup(opts)
        Snacks.toggle.new({
            id = "hardtime",
            name = "Hardtime",
            get = function() return require("hardtime").is_plugin_enabled end,
            set = function(state)
                if state then require("hardtime").enable() else require("hardtime").disable() end
            end,
        }):map("<leader>um")
        vim.keymap.set("n", "<leader>ur", function() vim.cmd("Hardtime report") end, { desc = "Hardtime report" })
    end,
}
