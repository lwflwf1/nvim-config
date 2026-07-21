return {
    {
        "folke/sidekick.nvim",
        cmd = { "Sidekick" },
        opts = {
            nes = { enabled = false },
        },
        keys = {
            { "<leader>st", "<cmd>Sidekick cli toggle<CR>", desc = "Sidekick toggle terminal" },
            { "<leader>ss", "<cmd>Sidekick cli select<CR>", desc = "Sidekick select CLI" },
            { "<leader>sf", function() require("sidekick.cli").send({ msg = "{file}" }) end, desc = "Sidekick send file" },
            { "<leader>se", function() require("sidekick.cli").send({ msg = "Explain {this}" }) end, desc = "Sidekick explain" },
        },
    },
}
