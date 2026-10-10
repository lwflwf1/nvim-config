return {
    "folke/trouble.nvim",
    cmd = "Trouble",
    keys = {
        -- Buffer diagnostics (lowercase)
        { "<leader>la", "<cmd>Trouble diagnostics toggle filter.buf=0<CR>", desc = "Toggle Diagnostics Buffer (Trouble)" },
        { "<leader>le", "<cmd>Trouble diagnostics toggle filter.buf=0 filter.severity=vim.diagnostic.severity.ERROR<CR>", desc = "Toggle Buffer Error (Trouble)" },
        { "<leader>lw", "<cmd>Trouble diagnostics toggle filter.buf=0 filter.severity=vim.diagnostic.severity.WARN<CR>", desc = "Toggle Buffer Warning (Trouble)" },
        { "<leader>lh", "<cmd>Trouble diagnostics toggle filter.buf=0 filter.severity={vim.diagnostic.severity.HINT,vim.diagnostic.severity.INFO}<CR>", desc = "Toggle Buffer Hint/Info (Trouble)" },
        -- All diagnostics (uppercase)
        { "<leader>lA", "<cmd>Trouble diagnostics toggle<CR>", desc = "Toggle Diagnostics All (Trouble)" },
        { "<leader>lE", "<cmd>Trouble diagnostics toggle filter.severity=vim.diagnostic.severity.ERROR<CR>", desc = "Toggle All Error (Trouble)" },
        { "<leader>lW", "<cmd>Trouble diagnostics toggle filter.severity=vim.diagnostic.severity.WARN<CR>", desc = "Toggle All Warning (Trouble)" },
        { "<leader>lH", "<cmd>Trouble diagnostics toggle filter.severity={vim.diagnostic.severity.HINT,vim.diagnostic.severity.INFO}<CR>", desc = "Toggle All Hint/Info (Trouble)" },
        -- LSP
        { "<leader>ll", "<cmd>Trouble lsp toggle focus=false win.position=right<CR>", desc = "Toggle LSP (Trouble)" },
        -- Quickfix & Location List
        { "<leader>lq", "<cmd>Trouble qflist toggle<CR>", desc = "Toggle Quickfix (Trouble)" },
        { "<leader>lk", "<cmd>Trouble loclist toggle<CR>", desc = "Toggle Location List (Trouble)" },
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
