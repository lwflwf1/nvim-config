return {
    {
        "stevearc/overseer.nvim",
        cmd = { "OverseerRun", "OverseerToggle", "OverseerTaskAction" },
        keys = {
            { "<F5>", "<cmd>OverseerRun<CR>", desc = "Run task" },
            { "<F9>", "<cmd>OverseerBuild<CR>", desc = "Build task" },
            { "<F10>", "<cmd>OverseerToggle<CR>", desc = "Toggle task list" },
        },
        opts = {
            task_list = {
                direction = "bottom",
                min_height = 8,
                max_height = { 20, 0.2 },
            },
            form = {
                border = "rounded",
            },
            task_win = {
                border = "rounded",
            },
        },
    },
}
