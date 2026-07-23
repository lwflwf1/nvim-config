return {
    "akinsho/git-conflict.nvim",
    keys = {
        { "]x", function() require("git-conflict").next_conflict() end, desc = "Next conflict" },
        { "[x", function() require("git-conflict").prev_conflict() end, desc = "Prev conflict" },
    },
    opts = {
        default_mappings = true,
        disable_diagnostics = false,
    },
}
