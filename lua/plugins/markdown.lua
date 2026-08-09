return {
    {
        "iamcco/markdown-preview.nvim",
        ft = "markdown",
        build = function()
            vim.fn["mkdp#util#install"]()
        end,
        keys = {
            { "<leader>mM", "<cmd>MarkdownPreviewToggle<CR>", desc = "Markdown preview", ft = "markdown" },
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
        "kaymmm/bullets.nvim",
        ft = { "markdown", "text", "gitcommit", "scratch" },
        opts = {
            empty_buffers = false,
            file_types = { "markdown", "text", "gitcommit", "scratch" },
            line_spacing = 2,
        },
    },
    {
        "hedyhli/markdown-toc.nvim",
        ft = "markdown",
        cmd = { "Mtoc" },
        main = "mtoc",
        opts = {},
    },
    {
        "OXY2DEV/markview.nvim",
        ft = { "markdown", "quarto", "rmd", "typst", "yaml", "Avante" },
        dependencies = { "nvim-treesitter/nvim-treesitter" },
        config = function()
            require("markview").setup({
                preview = {
                    enable_hybrid_mode = true,
                    icon_provider = "devicons",
                    modes = { "n", "no", "c", "i" },
                    hybrid_modes = { "i" },
                    edit_range = { 0, 0 },
                    filetypes = { "markdown", "quarto", "rmd", "typst", "yaml", "Avante" },
                },
                markdown_inline = {
                    checkboxes = {
                        checked = { scope_hl = false },
                        unchecked = { scope_hl = false },
                    },
                },
            })
            vim.keymap.set("n", "<leader>mm", "<cmd>Markview<CR>", { desc = "Toggle markview preview" })
            vim.keymap.set("n", "<leader>mh", "<cmd>Markview HybridToggle<CR>", { desc = "Toggle markview hybrid mode" })
        end,
    },
    {
        "jakewvincent/mkdnflow.nvim",
        ft = { "markdown", "rmd" },
        opts = {
            mappings = {
                MkdnFollowLink = { "n", "<leader>mf" },
                MkdnGoBack = { "n", "<leader>mb" },
                MkdnGoForward = { "n", "<leader>md" },
                MkdnNextHeading = { "n", "<leader>mj" },
                MkdnPrevHeading = { "n", "<leader>mk" },
                MkdnIncreaseHeading = { { "n", "v" }, "<leader>m+" },
                MkdnDecreaseHeading = { { "n", "v" }, "<leader>m-" },
                MkdnToggleToDo = { { "n", "v" }, "<leader>mt" },
                MkdnNewListItemBelowInsert = { "n", "o" },
                MkdnNewListItemAboveInsert = { "n", "O" },
                MkdnTableNextCell = { "i", "<Tab>" },
                MkdnTablePrevCell = { "i", "<S-Tab>" },
                MkdnFoldSection = false,
                MkdnUnfoldSection = false,
                MkdnCreateLinkFromClipboard = false,
            },
        },
    },
    {
        "HakonHarnes/img-clip.nvim",
        event = "VeryLazy",
        opts = {
            default = {
                dir_path = "assets",
                template = "$FILE_PATH",
            },
            filetypes = {
                markdown = {
                    template = "![$CURSOR]($FILE_PATH)",
                },
            },
        },
        keys = {
            { "<leader>mp", "<cmd>PasteImage<cr>", desc = "Paste image from clipboard" },
        },
    },
}
