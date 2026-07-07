return {
    {
        "vimwiki/vimwiki",
        cmd = { "VimwikiIndex", "VimwikiDiaryIndex" },
        config = function()
            vim.g.vimwiki_list = {
                {
                    path = vim.fn.stdpath("data") .. "/vimwiki",
                    syntax = "markdown",
                    ext = ".md",
                },
            }
        end,
    },
}
