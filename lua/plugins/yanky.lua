return {
    "gbprod/yanky.nvim",
    dependencies = { "folke/snacks.nvim" },
    opts = {
        ring = {
            history_length = 100,
            storage = "shada",
            sync_with_numbered_registers = true,
            cancel_event = "update",
            ignore_registers = { "_" },
        },
        highlight = {
            on_put = false,
            on_yank = false,
        },
        preserve_cursor_position = {
            enabled = true,
        },
        system_clipboard = {
            sync_with_ring = true,
        },
        textobj = {
            enabled = true,
        },
    },
    config = function(_, opts)
        require("yanky").setup(opts)
        vim.keymap.set({ "o", "x" }, "iy", function()
            require("yanky.textobj").last_put()
        end, { desc = "Last put text object" })
    end,
    keys = {
        { "y", "<Plug>(YankyYank)", mode = { "n", "x" }, desc = "Yank text" },
        { "p", "<Plug>(YankyPutAfter)", mode = { "n", "x" }, desc = "Put after" },
        { "P", "<Plug>(YankyPutBefore)", mode = { "n", "x" }, desc = "Put before" },
        { "gp", "<Plug>(YankyGPutAfter)", mode = { "n", "x" }, desc = "Put after, leave cursor" },
        { "gP", "<Plug>(YankyGPutBefore)", mode = { "n", "x" }, desc = "Put before, leave cursor" },
        { "[y", "<Plug>(YankyPreviousEntry)", desc = "Previous yank entry" },
        { "]y", "<Plug>(YankyNextEntry)", desc = "Next yank entry" },
        { "]p", "<Plug>(YankyPutIndentAfterLinewise)", desc = "Put indented after (linewise)" },
        { "[p", "<Plug>(YankyPutIndentBeforeLinewise)", desc = "Put indented before (linewise)" },
        { "]P", "<Plug>(YankyPutIndentAfterLinewise)", desc = "Put indented after (linewise)" },
        { "[P", "<Plug>(YankyPutIndentBeforeLinewise)", desc = "Put indented before (linewise)" },
        { "=p", "<Plug>(YankyPutAfterFilter)", desc = "Put after and reindent" },
        { "=P", "<Plug>(YankyPutBeforeFilter)", desc = "Put before and reindent" },
    },
}
