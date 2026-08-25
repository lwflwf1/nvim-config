return {
    {
        "ThePrimeagen/harpoon",
        branch = "harpoon2",
        dependencies = { "nvim-lua/plenary.nvim" },
        keys = {
            { "<leader>ha", function() require("harpoon"):list():add() end,                                    desc = "Harpoon add file" },
            { "<leader>hh", function() require("harpoon").ui:toggle_quick_menu(require("harpoon"):list()) end, desc = "Harpoon toggle menu" },
            { "<leader>1",  function() require("harpoon"):list():select(1) end,                                desc = "Harpoon 1" },
            { "<leader>2",  function() require("harpoon"):list():select(2) end,                                desc = "Harpoon 2" },
            { "<leader>3",  function() require("harpoon"):list():select(3) end,                                desc = "Harpoon 3" },
            { "<leader>4",  function() require("harpoon"):list():select(4) end,                                desc = "Harpoon 4" },
            { "<leader>5",  function() require("harpoon"):list():select(5) end,                                desc = "Harpoon 5" },
            { "<leader>6",  function() require("harpoon"):list():select(6) end,                                desc = "Harpoon 6" },
            { "<leader>7",  function() require("harpoon"):list():select(7) end,                                desc = "Harpoon 7" },
            { "<leader>8",  function() require("harpoon"):list():select(8) end,                                desc = "Harpoon 8" },
            { "<leader>9",  function() require("harpoon"):list():select(9) end,                                desc = "Harpoon 9" },
            { "<leader>0",  function() require("harpoon"):list():select(10) end,                               desc = "Harpoon 10" },
            { "<leader>hp", function() require("harpoon"):list():prev() end,                                   desc = "Harpoon prev" },
            { "<leader>hn", function() require("harpoon"):list():next() end,                                   desc = "Harpoon next" },
        },
        config = function()
            require("harpoon").setup({
                settings = {
                    key = function()
                        local root = vim.fs.root(0, require("config.project").markers)
                        return root or vim.uv.cwd()
                    end,
                },
            })

            local harpoon = require("harpoon")
            local extensions = require("harpoon.extensions")

            harpoon:extend(extensions.builtins.highlight_current_file())
            harpoon:extend(extensions.builtins.navigate_with_number())

            harpoon:extend({
                UI_CREATE = function(cx)
                    vim.keymap.set("n", "<C-s>", function()
                        harpoon.ui:select_menu_item({ split = true })
                    end, { buffer = cx.bufnr, desc = "Open in split" })
                    vim.keymap.set("n", "<C-v>", function()
                        harpoon.ui:select_menu_item({ vsplit = true })
                    end, { buffer = cx.bufnr, desc = "Open in vsplit" })
                    vim.keymap.set("n", "<C-t>", function()
                        harpoon.ui:select_menu_item({ tabedit = true })
                    end, { buffer = cx.bufnr, desc = "Open in tab" })
                end,
            })
        end,
    },
}
