local root_markers = require("config.root_markers")

local function get_project_root()
    return vim.fs.root(0, root_markers) or vim.fn.getcwd()
end

local function base_path()
    return "/proj/crane/wa/" .. vim.fn.expand("$USER")
end

local function switch_project_file()
    local bp = base_path()
    local abs_path = vim.api.nvim_buf_get_name(0)
    if abs_path == "" then
        vim.notify("No file in buffer", vim.log.levels.WARN)
        return
    end
    if vim.fn.stridx(abs_path, bp) ~= 0 then
        vim.notify("File not under " .. bp, vim.log.levels.WARN)
        return
    end
    local rel = abs_path:sub(#bp + 2)
    local parts = vim.split(rel, "/")
    local cur_project = parts[1]
    local file_rel = table.concat({ unpack(parts, 2) }, "/")

    local projects = {}
    local handle = vim.uv.fs_scandir(bp)
    if handle then
        while true do
            local name, typ = vim.uv.fs_scandir_next(handle)
            if not name then break end
            if typ == "directory" and name ~= cur_project then
                table.insert(projects, name)
            end
        end
    end
    if #projects == 0 then
        vim.notify("No other projects found", vim.log.levels.WARN)
        return
    end

    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")
    pickers.new({}, {
        prompt_title = "Switch project (" .. cur_project .. ")",
        finder = finders.new_table({ results = projects }),
        sorter = require("telescope.config").values.generic_sorter({}),
        attach_mappings = function(bufnr, _)
            actions.select_default:replace(function()
                actions.close(bufnr)
                local sel = action_state.get_selected_entry().value
                vim.cmd("edit " .. vim.fn.fnameescape(bp .. "/" .. sel .. "/" .. file_rel))
            end)
            return true
        end,
    }):find()
end

local function find_files_in_project()
    local bp = base_path()
    local projects = { "[Enter path...]" }
    local handle = vim.uv.fs_scandir(bp)
    if handle then
        while true do
            local name, typ = vim.uv.fs_scandir_next(handle)
            if not name then break end
            if typ == "directory" then
                table.insert(projects, name)
            end
        end
    end

    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")
    pickers.new({}, {
        prompt_title = "Search root",
        finder = finders.new_table({ results = projects }),
        sorter = require("telescope.config").values.generic_sorter({}),
        attach_mappings = function(bufnr, _)
            actions.select_default:replace(function()
                actions.close(bufnr)
                local sel = action_state.get_selected_entry().value
                local cwd
                if sel == "[Enter path...]" then
                    cwd = vim.fn.input("Search directory: ", bp .. "/")
                else
                    cwd = bp .. "/" .. sel
                end
                if cwd and cwd ~= "" then
                    require("telescope.builtin").find_files({ cwd = cwd, no_ignore = true })
                end
            end)
            return true
        end,
    }):find()
end

return {
    {
        "nvim-telescope/telescope.nvim",
        cmd = "Telescope",
        dependencies = {
            "nvim-lua/plenary.nvim",
            { "nvim-telescope/telescope-fzf-native.nvim", build = vim.fn.has("win32") == 1 and "cmake -S. -Bbuild -DCMAKE_BUILD_TYPE=Release && cmake --build build --config Release --target install" or "make" },
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
            { "<leader>foh", "<cmd>Telescope orgmode headlines<CR>", desc = "Org headlines" },
            { "<leader>fos", "<cmd>Telescope orgmode search<CR>", desc = "Org search" },
            { "<leader>fof", "<cmd>Telescope orgmode files<CR>", desc = "Org files" },
            { "<leader>fot", "<cmd>Telescope orgmode search_tags<CR>", desc = "Org tags" },
            { "<leader>for", "<cmd>Telescope orgmode refile_heading<CR>", desc = "Org refile" },
            { "<leader>foi", "<cmd>Telescope orgmode insert_link<CR>", desc = "Org insert link" },
            { "<leader>fp", switch_project_file, desc = "Open same file in another project" },
            { "<leader>fP", find_files_in_project, desc = "Find files in custom project root" },
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
            pcall(telescope.load_extension, "orgmode")
        end,
    },
}
