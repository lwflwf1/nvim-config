return {
    "aikhe/wrapped.nvim",
    -- Dashboard over this config repo's git history: commit heatmap/streaks,
    -- plugin count + growth chart, file and config-size stats. Everything is
    -- local (git + lazy + volt); default `path` is stdpath("config") = this repo.
    dependencies = { "nvzone/volt" },
    cmd = { "WrappedNvim" },
    keys = {
        { "<leader>uW", "<cmd>WrappedNvim<CR>", desc = "open WrappedNvim" },
    },
    opts = {},
}
