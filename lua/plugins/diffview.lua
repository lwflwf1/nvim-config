return {
    "sindrets/diffview.nvim",
    cmd = { "DiffviewOpen", "DiffviewFileHistory" },
    keys = {
        {
            "<leader>gv",
            function()
                local lib = require("diffview.lib")
                local view = lib.get_current_view()
                if view then
                    vim.cmd("DiffviewClose")
                else
                    vim.cmd("DiffviewOpen")
                end
            end,
            desc = "Diffview toggle",
        },
        { "<leader>gV", "<cmd>DiffviewFileHistory<CR>", desc = "Diffview history" },
        { "<leader>gt", "<cmd>DiffviewToggleFiles<CR>", desc = "Diffview toggle files" },
        { "<leader>gF", "<cmd>DiffviewFocusFiles<CR>", desc = "Diffview focus files" },
    },
    opts = {},
}
