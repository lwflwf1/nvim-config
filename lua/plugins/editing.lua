return {
    {
        "tpope/vim-surround",
        keys = {
            { "cs", mode = "n", desc = "Change surround" },
            { "ds", mode = "n", desc = "Delete surround" },
            { "ys", mode = "n", desc = "Add surround" },
            { "S", mode = "v", desc = "Add surround visual" },
        },
    },
    {
        "tpope/vim-repeat",
        keys = ".",
    },
    {
        "folke/ts-comments.nvim",
        event = { "BufReadPre", "BufNewFile" },
        opts = {
            lang = {
                tc = "# %s",
            },
        },
    },
    {
        url = "https://git.disroot.org/andyg/leap.nvim",
        keys = {
            { ";s", mode = { "n", "x" }, desc = "Leap forward" },
            { ";S", mode = { "n", "x" }, desc = "Leap backward" },
        },
        config = function()
            local leap = require("leap")
            leap.opts.safe_labels = {}
            vim.keymap.set({ "n", "x" }, ";s", function()
                leap.leap({ windows = { vim.fn.win_getid() } })
            end, { desc = "Leap forward" })
            vim.keymap.set({ "n", "x" }, ";S", function()
                leap.leap({ windows = { vim.fn.win_getid() }, backward = true })
            end, { desc = "Leap backward" })
        end,
    },
    {
        "windwp/nvim-autopairs",
        event = "InsertEnter",
        opts = {
            check_ts = true,
            ts_config = {
                lua = { "string" },
                javascript = { "template_string" },
            },
            disable_filetype = { "TelescopePrompt", "vim" },
            fast_wrap = {
                map = "<M-e>",
                chars = { "{", "[", "(", '"', "'" },
                pattern = [=[[%'%"%)%>%]%)%}%,]]=],
                end_key = "$",
                keys = "qwertyuiopzxcvbnmasdfghjkl",
                check_comma = true,
                highlight = "PmenuSel",
                highlight_grey = "LineNr",
            },
        },
    },
    {
        "junegunn/vim-easy-align",
        keys = {
            { "ga", "<Plug>(EasyAlign)", mode = { "n", "x" }, desc = "Easy align" },
        },
    },
    {
        "mg979/vim-visual-multi",
        keys = {
            { "<C-n>", "<Plug>(VM-Add-Cursor)", desc = "Add cursor" },
            { "<C-j>", "<Plug>(VM-Add-Cursor-Down)", desc = "Add cursor down" },
            { "<C-k>", "<Plug>(VM-Add-Cursor-Up)", desc = "Add cursor up" },
        },
        config = function()
            vim.g.VM_maps = {
                ["Add Cursor Down"] = "<C-j>",
                ["Add Cursor Up"] = "<C-k>",
            }
        end,
    },
    {
        "AndrewRadev/switch.vim",
        cmd = "Switch",
        keys = {
            { "ts", ":Switch<CR>", desc = "Switch", mode = "n" },
        },
        config = function()
            vim.g.switch_mapping = ""
            vim.g.switch_custom_definitions = {
                { "&", "|" },
                { "~", "!" },
                { "always_ff", "always_latch", "always_comb" },
                { "posedge", "negedge" },
                { "logic", "bit" },
                { "@", "wait" },
                { " <=", " =" },
                { "input", "output", "ref" },
                { "'b", "'h", "'d" },
                { "endfunction", "endtask", "endclass", "endinterface", "endmodule", "end", "endclocking" },
                { "function", "task" },
                { "WRITE", "READ" },
            }
        end,
    },
    {
        "RRethy/vim-illuminate",
        enabled = false,
        event = { "BufReadPre", "BufNewFile" },
        config = function()
            vim.g.Illuminate_ftblacklist = {
                "help", "qf", "far", "leaderf", "vista",
                "floaterm", "markdown", "git", "gitcommit",
                "org", "orgagenda",
            }
        end,
    },
    {
        "mbbill/undotree",
        cmd = "UndotreeToggle",
        keys = {
            { "<leader>u", "<cmd>UndotreeToggle<CR>", desc = "Undo tree" },
        },
    },
    {
        "folke/which-key.nvim",
        event = "VeryLazy",
        opts = {
            delay = 300,
            icons = { mappings = false },
            spec = {
                { "<leader>", group = "Leader" },
                { "g", group = "Goto" },
            },
        },
    },
    {
        "svermeulen/vim-subversive",
        keys = {
            { "s", "<plug>(SubversiveSubstitute)", mode = { "n", "x" }, desc = "Substitute" },
            { "ss", "<plug>(SubversiveSubstituteLine)", desc = "Substitute line" },
            { "S", "<plug>(SubversiveSubstituteToEndOfLine)", desc = "Substitute to EOL" },
        },
    },
    {
        "yianwillis/vimcdoc",
        event = "VeryLazy",
    },
}
