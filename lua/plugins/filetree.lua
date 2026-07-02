return {
    {
        "nvim-tree/nvim-tree.lua",
        cmd = { "NvimTreeToggle", "NvimTreeOpen", "NvimTreeClose" },
        keys = {
            { "<leader>e", "<cmd>NvimTreeToggle<CR>", desc = "Toggle file tree" },
        },
        opts = {
            disable_netrw = true,
            hijack_cursor = true,
            sync_root_with_cwd = true,
            respect_buf_cwd = true,
            update_focused_file = {
                enable = true,
                update_root = {
                    enable = true,
                },
            },
            view = {
                side = "left",
                width = 35,
            },
            renderer = {
                indent_markers = { enable = true },
            },
            filters = {
                dotfiles = false,
            },
            actions = {
                open_file = {
                    quit_on_open = false,
                    resize_window = false,
                },
            },
        },
    },
}
