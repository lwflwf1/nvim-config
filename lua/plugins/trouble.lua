return {
    "folke/trouble.nvim",
    cmd = "Trouble",
    keys = {
        -- Buffer diagnostics (lowercase)
        { "<leader>la", "<cmd>Trouble diagnostics toggle filter.buf=0<CR>", desc = "Diagnostics Buffer (Trouble)" },
        { "<leader>le", "<cmd>Trouble diagnostics toggle filter.buf=0 filter.severity=vim.diagnostic.severity.ERROR<CR>", desc = "Buffer Error (Trouble)" },
        { "<leader>lw", "<cmd>Trouble diagnostics toggle filter.buf=0 filter.severity=vim.diagnostic.severity.WARN<CR>", desc = "Buffer Warning (Trouble)" },
        { "<leader>lh", "<cmd>Trouble diagnostics toggle filter.buf=0 filter.severity={vim.diagnostic.severity.HINT,vim.diagnostic.severity.INFO}<CR>", desc = "Buffer Hint/Info (Trouble)" },
        -- All diagnostics (uppercase)
        { "<leader>lA", "<cmd>Trouble diagnostics toggle<CR>", desc = "Diagnostics All (Trouble)" },
        { "<leader>lE", "<cmd>Trouble diagnostics toggle filter.severity=vim.diagnostic.severity.ERROR<CR>", desc = "All Error (Trouble)" },
        { "<leader>lW", "<cmd>Trouble diagnostics toggle filter.severity=vim.diagnostic.severity.WARN<CR>", desc = "All Warning (Trouble)" },
        { "<leader>lH", "<cmd>Trouble diagnostics toggle filter.severity={vim.diagnostic.severity.HINT,vim.diagnostic.severity.INFO}<CR>", desc = "All Hint/Info (Trouble)" },
        -- LSP
        { "<leader>ll", "<cmd>Trouble lsp toggle focus=false win.position=right<CR>", desc = "LSP (Trouble)" },
        -- Quickfix & Location List
        { "<leader>lq", "<cmd>Trouble qflist toggle<CR>", desc = "Quickfix (Trouble)" },
        { "<leader>lk", "<cmd>Trouble loclist toggle<CR>", desc = "Location List (Trouble)" },
    },
    specs = {
        "ibhagwan/fzf-lua",
        opts = function(_, opts)
            local config = require("fzf-lua.config")
            local actions = require("trouble.sources.fzf").actions
            config.defaults.actions.files["ctrl-t"] = actions.open
        end,
    },
    init = function()
        vim.api.nvim_create_autocmd("QuickFixCmdPost", {
            callback = function()
                vim.cmd([[Trouble qflist open]])
            end,
        })
    end,
    opts = {},
}
