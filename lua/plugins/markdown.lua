return {
    {
        "iamcco/markdown-preview.nvim",
        ft = "markdown",
        build = function()
            vim.fn["mkdp#util#install"]()
        end,
        keys = {
            { "<leader>m", "<cmd>MarkdownPreviewToggle<CR>", desc = "Markdown preview", ft = "markdown" },
        },
        config = function()
            vim.g.mkdp_auto_start = 0
            vim.g.mkdp_auto_close = 1
            vim.g.mkdp_refresh_slow = 0
            vim.g.mkdp_command_for_global = 0
            vim.g.mkdp_open_to_the_world = 0
            vim.g.mkdp_open_ip = ""
            vim.g.mkdp_browser = ""
            vim.g.mkdp_echo_preview_url = 0
            vim.g.mkdp_browserfunc = ""
            vim.g.mkdp_preview_options = {
                mkit = {},
                katex = {},
                uml = {},
                maid = {},
                disable_sync_scroll = 0,
                sync_scroll_type = "middle",
                hide_yaml_meta = 1,
                sequence_diagrams = {},
                flowchart_diagrams = {},
                content_editable = false,
                disable_filename = 0,
            }
            vim.g.mkdp_markdown_css = ""
            vim.g.mkdp_highlight_css = ""
            vim.g.mkdp_port = ""
            vim.g.mkdp_page_title = "「${name}」"
            vim.g.mkdp_filetypes = { "markdown" }
        end,
    },
    {
        "dhruvasagar/vim-table-mode",
        ft = "markdown",
        keys = {
            { "<leader>tb", "<cmd>TableModeEnable<CR>", desc = "Table mode", mode = "n" },
                    { "<leader>tt", "<cmd>TableModeTableize<CR>", desc = "Tableize", mode = "n" },
        },
        config = function()
            vim.g.table_mode_tableize_map = "<Leader>tb"
            vim.g.table_mode_tableize_d_map = "<Leader>tt"
            vim.g.table_mode_corner = "|"
        end,
    },
    {
        "bullets-vim/bullets.vim",
        ft = { "markdown", "text", "gitcommit", "scratch" },
        config = function()
            vim.g.bullets_enabled_file_types = {
                "markdown", "text", "gitcommit", "scratch",
            }
            vim.g.bullets_enable_in_empty_buffers = 0
            vim.g.bullets_line_spacing = 2
        end,
    },
    {
        "mzlogin/vim-markdown-toc",
        ft = "markdown",
        cmd = { "GenTocGFM", "GenTocGitHub", "GenTocRedcarpet", "GenTocMarked", "UpdateTimeStamps" },
    },
}
