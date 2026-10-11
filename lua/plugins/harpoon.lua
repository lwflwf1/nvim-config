return {
    {
        "ThePrimeagen/harpoon",
        branch = "harpoon2",
        dependencies = { "nvim-lua/plenary.nvim" },
        keys = {
            { "<leader>ha", function()
                require("harpoon"):list():add()
                vim.notify("Harpoon add current file", vim.log.levels.INFO)
            end, desc = "Harpoon add file" },
            { "<leader>hh", function() require("harpoon").ui:toggle_quick_menu(require("harpoon"):list()) end, desc = "Toggle Harpoon menu" },
            { "<leader>hp", function() require("harpoon"):list():prev() end,                                   desc = "Harpoon prev" },
            { "<leader>hn", function() require("harpoon"):list():next() end,                                   desc = "Harpoon next" },
        },
        config = function()
            -- The `Harpoon` class type describes the resolved instance, not the
            -- partial setup() opts it accepts at runtime.
            ---@diagnostic disable-next-line: missing-fields
            require("harpoon").setup({
                settings = {
                    key = function()
                        return vim.fn.getcwd()
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
