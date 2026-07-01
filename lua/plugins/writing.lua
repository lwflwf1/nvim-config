return {
    {
        "vimwiki/vimwiki",
        ft = "vimwiki",
        cmd = { "VimwikiIndex", "VimwikiDiaryIndex" },
        config = function()
            vim.g.vimwiki_list = {
                {
                    path = vim.g.data_dir .. "vimwiki",
                    syntax = "markdown",
                    ext = ".md",
                },
            }
        end,
    },
}
