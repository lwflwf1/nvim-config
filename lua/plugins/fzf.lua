local project_root = require("config.project").project_root

local exclude_patterns = {
    ".git", "node_modules", "build", "dist",
    "*.o", "*.obj", "*.so", "*.dll", "*.exe",
    "*.pyc", "*.png", "*.jpg", "*.pdf",
}

local function rg_glob_exclude()
    local parts = {}
    for _, p in ipairs(exclude_patterns) do
        table.insert(parts, "-g !" .. p)
    end
    return table.concat(parts, " ")
end

local function fd_glob_exclude()
    local parts = {}
    for _, p in ipairs(exclude_patterns) do
        table.insert(parts, "--exclude " .. p)
    end
    return table.concat(parts, " ")
end

function _G.grep_textobj()
    local start_pos = vim.api.nvim_buf_get_mark(0, '[')
    local end_pos = vim.api.nvim_buf_get_mark(0, ']')
    local lines = vim.api.nvim_buf_get_lines(0, start_pos[1]-1, end_pos[1], false)
    if #lines == 0 then return end
    if #lines == 1 then
        lines[1] = string.sub(lines[1], start_pos[2]+1, end_pos[2])
    else
        lines[1] = string.sub(lines[1], start_pos[2]+1)
        lines[#lines] = string.sub(lines[#lines], 1, end_pos[2])
    end
    local search = lines[1]:gsub("^%s*(.-)%s*$", "%1")
    if search == "" then
        local text = table.concat(lines, '\n')
        search = text:sub(1, 80)
    end
    if search ~= "" then require("fzf-lua").grep({ search = search }) end
end

vim.keymap.set('n', '<leader>fo', function()
    vim.o.operatorfunc = "v:lua.grep_textobj"
    vim.cmd('normal! g@')
end, { noremap = true, silent = true, desc = "Grep text object" })

local function get_project_root()
    return project_root(0) or vim.fn.getcwd()
end

local function proj_base_path()
    return "/proj/crane/wa/" .. vim.fn.expand("$USER")
end

local function scan_dirs(path)
    local dirs = {}
    local handle = vim.uv.fs_scandir(path)
    if handle then
        while true do
            local name, typ = vim.uv.fs_scandir_next(handle)
            if not name then break end
            if typ == "directory" then
                table.insert(dirs, name)
            end
        end
    end
    return dirs
end

local function switch_project_file()
    local bp = proj_base_path()
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

    local projects = scan_dirs(bp)
    projects = vim.tbl_filter(function(p) return p ~= cur_project end, projects)
    if #projects == 0 then
        vim.notify("No other projects found", vim.log.levels.WARN)
        return
    end

    require("fzf-lua").fzf_exec(projects, {
        prompt = "Switch project (" .. cur_project .. ")> ",
        actions = {
            ["default"] = function(selected)
                if selected and selected[1] then
                    vim.cmd("edit " .. vim.fn.fnameescape(bp .. "/" .. selected[1] .. "/" .. file_rel))
                end
            end,
        },
    })
end

local function find_files_in_project()
    local bp = proj_base_path()
    local projects = scan_dirs(bp)
    table.insert(projects, 1, "[Enter path...]")

    require("fzf-lua").fzf_exec(projects, {
        prompt = "Search root> ",
        actions = {
            ["default"] = function(selected)
                if not (selected and selected[1]) then return end
                -- Defer so the outer picker fully closes and restores the editor
                -- window before the nested files() picker opens; otherwise fzf-lua
                -- fails to open the selected file ("Unable to add buffer").
                vim.schedule(function()
                    local cwd
                    if selected[1] == "[Enter path...]" then
                        cwd = vim.fn.input("Search directory: ", bp .. "/")
                    else
                        cwd = bp .. "/" .. selected[1]
                    end
                    if cwd and cwd ~= "" then
                        -- Project dirs' contents live behind symlinks; fd doesn't
                        -- follow them by default (-L only when follow=true), which
                        -- yields an empty picker.
                        require("fzf-lua").files({ cwd = vim.fn.resolve(cwd), no_ignore = true, follow = true })
                    end
                end)
            end,
        },
    })
end

return {
    {
        "ibhagwan/fzf-lua",
        cmd = "FzfLua",
        dependencies = {
            "echasnovski/mini.nvim",
        },
        keys = {
            { "<leader>ff", function() require("fzf-lua").files({ cwd = get_project_root(), no_ignore = true }) end, desc = "Find files (project root)" },
            { "<leader>fg", function() require("fzf-lua").git_files() end, desc = "Find git files" },
            { "<leader>fm", function() require("fzf-lua").oldfiles() end, desc = "Recent files" },
            { "<leader>fu", function() require("fzf-lua").lsp_document_symbols() end, desc = "LSP document symbols" },
            { "<leader>fd", function() require("fzf-lua").lsp_references() end, desc = "LSP references" },
            { "<leader>fS", function() require("fzf-lua").lsp_workspace_symbols() end, desc = "LSP workspace symbols" },
            { "<leader>fF", function() require("fzf-lua").lsp_finder() end, desc = "LSP finder (all)" },
            { "<leader>fl", function() require("fzf-lua").blines() end, desc = "Buffer line fuzzy search" },
            { "<leader>fL", function() require("fzf-lua").lgrep_curbuf() end, desc = "Buffer line regex search" },
            { "<leader>f'", function() require("fzf-lua").registers() end, desc = "Registers" },
            { "<leader>f?", function() require("fzf-lua").keymaps() end, desc = "Keymaps" },
            { "<leader>fw", function() require("fzf-lua").grep_cword() end, desc = "Word search" },
            { "<leader>fn", function() local filename = vim.fn.expand("%:t") require("fzf-lua").grep({ search = filename }) end, desc = "Search current filename in text" },
            { "<leader>fr", function() require("fzf-lua").resume() end, desc = "Resume" },
            { "<leader>fb", function() require("fzf-lua").buffers() end, desc = "Buffers" },
            { "<leader>fc", function() require("fzf-lua").commands() end, desc = "Commands" },
            { "<leader>fh", function() require("fzf-lua").command_history() end, desc = "Command history" },
            { "<leader>fq", function() require("fzf-lua").quickfix() end, desc = "Quickfix" },
            { "<leader>fz", function() require("fzf-lua").live_grep() end, desc = "Live grep" },
            { "<leader>ft", function() require("fzf-lua").tags() end, desc = "Project tags" },
            { "<leader>fT", function() require("fzf-lua").btags() end, desc = "Buffer tags" },
            { "<leader>fp", switch_project_file, desc = "Open same file in another project" },
            { "<leader>fP", find_files_in_project, desc = "Find files in custom project root" },
        },
        opts = {
            file_icon_padding = " ",
            winopts = {
                height = 0.85,
                width = 0.85,
            },
            fzf_opts = {
                ["--pointer"] = ">",
                ["--marker"] = "+",
                ["--smart-case"] = true,
            },
            keymap = {
                fzf = {
                    ["ctrl-j"] = "down",
                    ["ctrl-k"] = "up",
                    ["ctrl-c"] = "abort",
                },
            },
            -- Follow symbolic links in all file-system searches (rg --follow /
            -- fd -L); the box's tree is full of symlinked dirs. grep.rg_opts must
            -- keep the full fzf-lua default string with -e last.
            grep = {
                rg_opts = "--column --line-number --no-heading --color=always --smart-case --max-columns=4096 --follow -e",
            },
            files = {
                follow = true,
                rg_opts = "--color=never --files " .. rg_glob_exclude(),
                fd_opts = "--color=never --type f --type l " .. fd_glob_exclude(),
            },
        },
    },
}
