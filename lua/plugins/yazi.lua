return {
    "mikavilpas/yazi.nvim",
    version = "*",
    enabled = not vim.g.is_rhel6,
    cmd = { "Yazi" },
    keys = {
        { "<leader>ey", mode = { "n", "v" }, "<cmd>Yazi<cr>", desc = "Yazi (current file)" },
        { "<leader>eY", "<cmd>Yazi cwd<cr>", desc = "Yazi (nvim cwd)" },
    },
    opts = {
        integrations = {
            -- grep goes through snacks.picker (the default would look for
            -- telescope, which is not installed); grug-far replace, bundled
            -- snacks bufdelete and the rest keep their defaults.
            grep_in_directory = function(directory)
                require("snacks").picker.grep({ dirs = { directory } })
            end,
            grep_in_selected_files = function(selected_files)
                require("snacks").picker.grep({ paths = selected_files })
            end,
            picker_add_copy_relative_path_action = "snacks.picker",
        },
    },
}
