local project_root = require("config.project").project_root

local function get_project_root()
    return project_root(0) or vim.fn.getcwd()
end

-- ============== fff-powered sources (Rust in-memory index) ==============
-- Engine: require("fff").file_search/content_search (see plugins/fff.lua).
-- Sync FFI calls from the finder coroutine; typical query <10ms against the
-- resident index (time_budget_ms=150 caps the worst-case grep).
--
-- Cold-start handling: fff's index initialises lazily and re-roots run on a
-- background thread, so the first query after startup/a project switch can
-- be empty. Instead of falling back to rg, we poll inside the finder's async
-- coroutine (ctx.async:sleep — non-blocking) and stream results in as soon
-- as the index is ready; a new keystroke aborts the poll automatically.

local fff_grep_mode = "regex"
local FFF_GREP_MODES = { "regex", "plain", "fuzzy" }

-- One-line hint shown as the input window's winbar (above the prompt). The mode
-- word mirrors fff_grep_mode; refreshed when the picker opens and on <a-r>.
local function fff_grep_hint()
    local label = fff_grep_mode:sub(1, 1):upper() .. fff_grep_mode:sub(2)
    return " " .. label .. " · <a-r> mode · *.sv · dir/ · !dir"
end

-- Push the current hint onto a live picker's input winbar (and the layout's
-- cached win opts so a layout rebuild keeps it).
local function fff_set_hint(picker)
    local text = fff_grep_hint()
    local w = picker.layout and picker.layout.wins and picker.layout.wins.input
    if not w then return end
    w.opts.wo.winbar = text
    local wo = picker.layout.win_opts and picker.layout.win_opts.input
    if wo and wo.wo then wo.wo.winbar = text end
    if w.win and vim.api.nvim_win_is_valid(w.win) then
        vim.wo[w.win].winbar = text
    end
end

-- While polling, wake every POLL_MS up to POLL_TRIES times (~6s).
local FFF_POLL_MS = 350
local FFF_POLL_TRIES = 17

-- Canonical form, for comparing a path with the Rust-side picker root.
-- Mirrors fff's ensure_indexed.canon: resolve the real path (Windows 8.3 short
-- names, symlinks) so it matches the Rust side's dunce::canonicalize base_path.
local function fff_norm(p)
    local abs = vim.fn.fnamemodify(vim.fn.expand(p), ":p"):gsub("[/\\]+$", "")
    local ok, real = pcall(function() return vim.uv.fs_realpath(abs) end)
    if ok and real then abs = real end
    local n = vim.fs.normalize(abs)
    if vim.fn.has("win32") == 1 then n = n:lower() end
    return n
end

-- Root held by the Rust picker (nil before it is initialised).
local function fff_rust_root()
    local ok, h = pcall(require("fff.rust").health_check)
    if ok and type(h) == "table" and h.file_picker then
        return h.file_picker.base_path
    end
end

-- Last target confirmed ready and when. health_check runs a git discover, so
-- cache the result instead of re-checking on every keystroke.
local fff_ready_root, fff_ready_at = nil, 0
local FFF_READY_TTL_MS = 2000

-- True when the Rust index is rooted at `target`; otherwise request the
-- background re-root and report not-ready so the caller polls instead of
-- returning the previous project's files.
local function fff_root_ready(target)
    local now = vim.uv.hrtime() / 1e6
    if fff_ready_root and now - fff_ready_at < FFF_READY_TTL_MS and fff_norm(fff_ready_root) == fff_norm(target) then
        return true
    end
    local root = fff_rust_root()
    if root and fff_norm(root) == fff_norm(target) then
        fff_ready_root, fff_ready_at = target, now
        return true
    end
    fff_ready_root = nil
    pcall(require("fff").change_indexing_directory, target)
    return false
end

-- Returns snacks items for a fff file_search query (max 200).
local function fff_files(q)
    local target = get_project_root()
    if not fff_root_ready(target) then return {} end
    local ok, res = pcall(require("fff").file_search, q, {
        max_results = 200,
        wait_for_index_ms = 0,
        cwd = target,
    })
    local items = {}
    if ok and res.items then
        local canon = require("fff.utils").canonicalize_fff_path
        for _, it in ipairs(res.items) do
            if it.type == "file" then
                local abs = canon(it.relative_path)
                if abs then
                    items[#items + 1] = { file = abs, text = abs }
                end
            end
        end
    end
    return items
end

local function fff_grep(q)
    local target = get_project_root()
    if not fff_root_ready(target) then return {} end
    local ok, res = pcall(require("fff").content_search, q, {
        page_size = 200,
        mode = fff_grep_mode,
        trim_whitespace = false,
        wait_for_index_ms = 0,
        cwd = target,
    })
    local items = {}
    if ok and res.items then
        local canon = require("fff.utils").canonicalize_fff_path
        for _, m in ipairs(res.items) do
            local abs = canon(m.relative_path)
            if abs then
                items[#items + 1] = {
                    file = abs,
                    text = abs,
                    -- fff: line 1-based, col 0-based byte offset — identical to snacks pos
                    pos = { m.line_number, m.col },
                    line = m.line_content or "",
                    positions = vim.tbl_map(function(r) return r[1] end, m.match_ranges or {}),
                }
            end
        end
    end
    return items
end

-- Wrap a snapshot query: when it has results, return them as a plain table
-- (fast path). When empty (index still warming up), return an async generator
-- that sleeps between retries and streams results in; snacks aborts it on the
-- next keystroke / picker close via ctx.async.
--
-- The first call runs on the main thread; the retries run in the finder's
-- fast-event context where vim API calls (project_root → nvim_buf_get_name)
-- are forbidden, so each retry hops back to the main thread via async:schedule.
local function fff_polling_finder(query_fn)
    return function(opts, ctx)
        local q = ctx.filter.search
        local items = query_fn(q)
        if #items > 0 then return items end

        return function(cb)
            local async = ctx.async
            local function poll() return query_fn(q) end
            for _ = 1, FFF_POLL_TRIES do
                if not async or not async:running() then return end
                async:sleep(FFF_POLL_MS) -- non-blocking; raises on abort
                local got = async:schedule(poll)
                if #got > 0 then
                    for _, item in ipairs(got) do cb(item) end
                    return
                end
            end
        end
    end
end

local fff_file_finder = fff_polling_finder(fff_files)

local fff_grep_polling = fff_polling_finder(fff_grep)
local fff_grep_finder = function(opts, ctx)
    -- empty query has no grep meaning; don't hand it to fff
    if ctx.filter.search == "" then return {} end
    return fff_grep_polling(opts, ctx)
end

local function fff_cycle_grep_mode(picker)
    local next_idx = 1
    for i, m in ipairs(FFF_GREP_MODES) do
        if m == fff_grep_mode then next_idx = (i % #FFF_GREP_MODES) + 1 end
    end
    fff_grep_mode = FFF_GREP_MODES[next_idx]
    fff_set_hint(picker)
    picker:find({ refresh = true })
end

local function fff_jump_file(picker, item, step)
    local items = picker:items()
    if not item or not item.idx then return end
    for i = item.idx + step, step > 0 and #items or 1, step do
        if items[i] and items[i].file ~= item.file then
            picker.list:_move(i, true, true)
            return
        end
    end
end

local fff_file_source = {
    finder = fff_file_finder,
    format = "file",
    live = true,
    supports_live = true,
}

-- The input must be 2 rows tall for the winbar to render (nvim drops a winbar
-- on a 1-row float), so grow the input child in the resolved layout tree.
local function fff_grep_layout(l)
    local function walk(node)
        for _, c in ipairs(node) do
            if c.win == "input" then c.height = (c.height or 1) + 1
            elseif c.box then walk(c) end
        end
    end
    walk(l.layout)
    return l
end

local fff_grep_source = {
    finder = fff_grep_finder,
    format = "file",
    live = true,
    supports_live = true,
    actions = {
        fff_mode = function(picker) fff_cycle_grep_mode(picker) end,
        fff_next_file = function(picker, item) fff_jump_file(picker, item, 1) end,
        fff_prev_file = function(picker, item) fff_jump_file(picker, item, -1) end,
    },
    layout = { config = fff_grep_layout },
    on_show = fff_set_hint,
    win = {
        input = {
            wo = { winbar = fff_grep_hint() },
            keys = {
                ["<a-r>"] = { "fff_mode", mode = { "i", "n" }, desc = "Cycle grep mode" },
                ["<a-n>"] = { "fff_next_file", mode = { "i", "n" }, desc = "Next file" },
                ["<a-p>"] = { "fff_prev_file", mode = { "i", "n" }, desc = "Prev file" },
            },
        },
    },
}

-- Seed a grep query from a literal string (shares the fff grep source: hint,
-- keys, regex default, polling).
local function fff_grep_seeded(text)
    return vim.tbl_extend("force", fff_grep_source, { search = text })
end

-- ============== end fff sources ==============

local exclude_patterns = {
    ".git", "node_modules", "build", "dist",
    "*.o", "*.obj", "*.so", "*.dll", "*.exe",
    "*.pyc", "*.png", "*.jpg", "*.pdf",
}

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
    if search ~= "" then Snacks.picker.pick(fff_grep_seeded(search)) end
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
            -- <leader>ff/fz/fw are driven by the fff engine (Rust in-memory index)
            { "<leader>ff", function() Snacks.picker.pick(fff_file_source) end, desc = "Find files (fff)" },
            { "<leader>fz", function() Snacks.picker.pick(fff_grep_source) end, desc = "Live grep (fff)" },
            { "<leader>fw", function()
                Snacks.picker.pick(vim.tbl_extend("force", fff_grep_source, {
                    search = function(picker) return picker:word() end,
                }))
              end, mode = { "n", "x" }, desc = "Search current word/selection (fff)" },
            { "<leader>fg", function() Snacks.picker.git_files() end, desc = "Find git files" },
            { "<leader>fm", function() Snacks.picker.smart() end, desc = "Smart find files" },
            { "<leader>fu", function() Snacks.picker.lsp_symbols() end, desc = "LSP document symbols" },
            { "<leader>fS", function() Snacks.picker.lsp_symbols({ workspace = true }) end, desc = "LSP workspace symbols" },
            { "<leader>fd", function() Snacks.picker.lsp_references() end, desc = "LSP references" },
            { "<leader>fl", function() Snacks.picker.lines() end, desc = "Buffer line fuzzy search" },
            { "<leader>fL", function() Snacks.picker.grep_buffers() end, desc = "Grep open buffers" },
            { "<leader>fn", function() Snacks.picker.pick(fff_grep_seeded(vim.fn.expand("%:t"))) end, desc = "Search current filename in text" },
            { "<leader>fr", function() Snacks.picker.resume() end, desc = "Resume" },
            { "<leader>fb", function() Snacks.picker.buffers() end, desc = "Buffers" },
            { "<leader>fc", function() Snacks.picker.commands() end, desc = "Commands" },
            { "<leader>fh", function() Snacks.picker.command_history() end, desc = "Command history" },
            { "<leader>fq", function() Snacks.picker.qflist() end, desc = "Quickfix" },
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
