local root_markers = require("config.root_markers")

local function get_project_root()
    return vim.fs.root(0, root_markers) or vim.fn.getcwd()
end

return {
    {
        "nvim-telescope/telescope.nvim",
        cmd = "Telescope",
        dependencies = {
            "nvim-lua/plenary.nvim",
            { "nvim-telescope/telescope-fzf-native.nvim", build = vim.g.os == "windows" and "cmake -S. -Bbuild -DCMAKE_BUILD_TYPE=Release && cmake --build build --config Release --target install" or "make" },
            "nvim-telescope/telescope-file-browser.nvim",
        },
        keys = {
            { "<leader>ff", function() require("telescope.builtin").find_files({ cwd = get_project_root(), no_ignore = true }) end, desc = "Find files (project root)" },
            { "<leader>fg", "<cmd>Telescope git_files<CR>", desc = "Find git files" },
            { "<leader>fm", "<cmd>Telescope oldfiles<CR>", desc = "Recent files" },
            { "<leader>fu", "<cmd>Telescope lsp_document_symbols<CR>", desc = "Functions" },
            { "<leader>fd", "<cmd>Telescope lsp_references<CR>", desc = "References" },
            { "<leader>fl", "<cmd>Telescope current_buffer_fuzzy_find<CR>", desc = "Line search" },
            { "<leader>fw", "<cmd>Telescope grep_string<CR>", desc = "Word search" },
            { "<leader>fr", "<cmd>Telescope resume<CR>", desc = "Resume" },
            { "<leader>fb", "<cmd>Telescope buffers<CR>", desc = "Buffers" },
            { "<leader>fc", "<cmd>Telescope commands<CR>", desc = "Commands" },
            { "<leader>fh", "<cmd>Telescope command_history<CR>", desc = "Command history" },
            { "<leader>fq", "<cmd>Telescope quickfix<CR>", desc = "Quickfix" },
            { "<leader>fs", "<cmd>Telescope live_grep<CR>", desc = "Live grep" },
            { "<leader>fe", "<cmd>Telescope file_browser<CR>", desc = "File browser" },
            { "<leader>ft", "<cmd>Telescope tags<CR>", desc = "Project tags" },
            { "<leader>fT", "<cmd>Telescope current_buffer_tags<CR>", desc = "Buffer tags" },
            { "<leader>fOh", "<cmd>Telescope orgmode headlines<CR>", desc = "Org headlines" },
            { "<leader>fOs", "<cmd>Telescope orgmode search<CR>", desc = "Org search" },
            { "<leader>fOf", "<cmd>Telescope orgmode files<CR>", desc = "Org files" },
        },
        config = function()
            local telescope = require("telescope")
            local actions = require("telescope.actions")

            telescope.setup({
                defaults = {
                    prompt_prefix = "  ",
                    selection_caret = "  ",
                    layout_strategy = "horizontal",
                    layout_config = {
                        horizontal = { width = 0.85, preview_cutoff = 120 },
                    },
                    mappings = {
                        i = {
                            ["<C-j>"] = actions.move_selection_next,
                            ["<C-k>"] = actions.move_selection_previous,
                            ["<C-l>"] = actions.select_default,
                            ["<C-c>"] = actions.close,
                        },
                    },
                    file_ignore_patterns = {
                        "node_modules", ".git/", "build/", "dist/",
                        "*.o", "*.obj", "*.so", "*.dll", "*.exe",
                        "*.pyc", "*.png", "*.jpg", "*.pdf",
                    },
                },
                extensions = {
                    fzf = {
                        fuzzy = true,
                        override_generic_sorter = true,
                        override_file_sorter = true,
                        case_mode = "smart_case",
                    },
                    file_browser = {
                        hidden = true,
                        grouped = true,
                    },
                },
            })

            pcall(telescope.load_extension, "fzf")
            pcall(telescope.load_extension, "file_browser")
        end,
    },
}
