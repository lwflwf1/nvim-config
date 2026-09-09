local project_root = require("config.project").project_root

local exclude_patterns = {
    ".git", "node_modules", "build", "dist",
    "*.o", "*.obj", "*.so", "*.dll", "*.exe",
    "*.pyc", "*.png", "*.jpg", "*.pdf",
}

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
    if search ~= "" then require("snacks").picker.grep({ search = search }) end
end

vim.keymap.set('n', '<leader>fo', function()
    vim.o.operatorfunc = "v:lua.grep_textobj"
    vim.cmd('normal! g@')
end, { noremap = true, silent = true, desc = "Grep text object" })

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

    require("snacks").picker.pick({
        prompt = "Switch project (" .. cur_project .. ")> ",
        items = vim.tbl_map(function(p) return { text = p } end, projects),
        format = "text",
        actions = {
            confirm = function(picker, item)
                picker:close()
                vim.cmd("edit " .. vim.fn.fnameescape(bp .. "/" .. item.text .. "/" .. file_rel))
            end,
        },
    })
end

-- Resolve a user-typed search root:
--   1. existing directory (absolute or relative) -> used as-is
--   2. bare project name -> prefix-matched against bp's subdirectories
--   3. anything else -> nil (notify + cancel)
local function resolve_search_root(v)
    v = v and v:gsub("%s+$", "") or ""
    if v == "" then return nil end
    if vim.fn.isdirectory(v) == 1 then return vim.fn.resolve(v) end
    local bp = proj_base_path()
    if not v:find("[/\\]") then
        local matches = vim.tbl_filter(function(p)
            return p:sub(1, #v):lower() == v:lower()
        end, scan_dirs(bp))
        if #matches == 1 then return bp .. "/" .. matches[1] end
        if #matches > 1 then
            vim.notify("Ambiguous project name: " .. v .. " (" .. table.concat(matches, ", ") .. ")", vim.log.levels.WARN)
            return nil
        end
    end
    vim.notify("Not a directory: " .. v, vim.log.levels.WARN)
    return nil
end

-- Interactive root input with Tab directory completion.
-- fG/fW preset the current project root; fP presets the project base path
-- so Tab completion naturally lists the project directories.
local function input_search_root(prompt, default, open)
    local v = vim.fn.input(prompt, default, "dir")
    print("")
    local root = resolve_search_root(v)
    if root then open(root) end
end

return {
    {
        "folke/snacks.nvim",
        keys = {
            { "<leader>ff", function() Snacks.picker.files({ cwd = get_project_root(), ignored = true, follow = true, exclude = exclude_patterns }) end, desc = "Find files (project root)" },
            { "<leader>fg", function() Snacks.picker.git_files() end, desc = "Find git files" },
            { "<leader>fm", function() Snacks.picker.smart() end, desc = "Smart find files" },
            { "<leader>fu", function() Snacks.picker.lsp_symbols() end, desc = "LSP document symbols" },
            { "<leader>fS", function() Snacks.picker.lsp_symbols({ workspace = true }) end, desc = "LSP workspace symbols" },
            { "<leader>fd", function() Snacks.picker.lsp_references() end, desc = "LSP references" },
            { "<leader>fl", function() Snacks.picker.lines() end, desc = "Buffer line fuzzy search" },
            { "<leader>fL", function() Snacks.picker.grep_buffers() end, desc = "Grep open buffers" },
            { "<leader>fw", function() Snacks.picker.grep_word() end, desc = "Word search" },
            { "<leader>fn", function() Snacks.picker.grep({ search = vim.fn.expand("%:t") }) end, desc = "Search current filename in text" },
            { "<leader>fr", function() Snacks.picker.resume() end, desc = "Resume" },
            { "<leader>fb", function() Snacks.picker.buffers() end, desc = "Buffers" },
            { "<leader>fc", function() Snacks.picker.commands() end, desc = "Commands" },
            { "<leader>fh", function() Snacks.picker.command_history() end, desc = "Command history" },
            { "<leader>fq", function() Snacks.picker.qflist() end, desc = "Quickfix" },
            { "<leader>fz", function() Snacks.picker.grep() end, desc = "Live grep" },
            { "<leader>ft", function() Snacks.picker.tags({ workspace = true }) end, desc = "Project tags" },
            { "<leader>fT", function() Snacks.picker.tags({ workspace = false }) end, desc = "Buffer tags" },
            { "<leader>f'", function() Snacks.picker.registers() end, desc = "Registers" },
            { "<leader>f?", function() Snacks.picker.keymaps() end, desc = "Keymaps" },
            { "<leader>fj", function() Snacks.picker.jumps() end, desc = "Jumps" },
            { "<leader>fk", function() Snacks.picker.marks() end, desc = "Marks" },
            { "<leader>fp", switch_project_file, desc = "Open same file in another project" },
            { "<leader>fP", function()
                input_search_root("Files root: ", proj_base_path() .. "/", function(root)
                    -- Project dirs' contents live behind symlinks; follow=true
                    -- is required for the files finder to see them.
                    Snacks.picker.files({ cwd = root, ignored = true, follow = true, exclude = exclude_patterns })
                end)
              end, desc = "Find files in custom root" },
            { "<leader>fG", function()
                input_search_root("Grep root: ", get_project_root(), function(root)
                    Snacks.picker.grep({ cwd = root })
                end)
              end, desc = "Live grep in custom root" },
            { "<leader>fW", function()
                input_search_root("Word search root: ", get_project_root(), function(root)
                    Snacks.picker.grep_word({ cwd = root })
                end)
              end, desc = "Word search in custom root" },
        },
    },
}
