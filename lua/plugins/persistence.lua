return {
    "folke/persistence.nvim",
    event = "BufReadPre",
    keys = {
        { "<leader>qq", function() require("persistence").select() end, desc = "Select Session" },
        { "<leader>qs", function() require("persistence").load() end, desc = "Restore Session" },
        { "<leader>ql", function() require("persistence").load({ last = true }) end, desc = "Restore Last Session" },
        { "<leader>qw", function() require("persistence").save() end, desc = "Save Session" },
        { "<leader>qt", function()
            -- No toggle API; active() + start()/stop() is the whole contract.
            local persistence = require("persistence")
            if persistence.active() then persistence.stop() else persistence.start() end
        end, desc = "Toggle Persistence" },
    },
    opts = {},
}
