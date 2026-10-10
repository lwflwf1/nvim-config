-- Smart gf/gF: open the file:line path under the cursor (quoted, file(line),
-- file:line, file;line, ...), falling back to the built-in gf/gF. In a
-- terminal buffer the path under the cursor (terminal output) opens in the
-- window of your choice -- a letter appears in each window; without a path
-- the letter just focuses that window (see box/winpick.lua).
-- setup() registers the two normal-mode maps.
local M = {}

-- Open file and jump to line
local smart_gf_config = {
    -- Characters wrapping the filename (add more, e.g. [[ or `)
    quote_chars = { '"', "'" },

    -- Line-number separators (add more, e.g. | or ->)
    separators = { ":", ";", ",", "(" },

    -- Characters to strip from the filename
    trim_chars = { '"', "'", " " },
}

-- Build the match patterns from the config (plain strings -- both capture
-- groups are always 1/2).
local function build_smart_gf_patterns()
    local patterns = {}

    -- 1. Quoted formats: "file", line or 'file', line
    for _, q in ipairs(smart_gf_config.quote_chars) do
        local q_esc = vim.pesc(q)
        table.insert(patterns, q_esc .. '([^' .. q_esc .. ']+)' .. q_esc .. ',?%s*(%d+)')
    end

    -- 2. file(line) format (UVM logs, compiler errors) — before :/;/,
    --    because a line like "path.sv(256) @ 123ns: ... for ctl_id:0" must
    --    match the file(256) part, not the later word:number (e.g. ctl_id:0).
    if vim.tbl_contains(smart_gf_config.separators, "(") then
        table.insert(patterns, '([^%s]+)%((%d+)%)')
    end

    -- 3. Unquoted formats with a separator: file:line, file;line, file, line.
    --    "(" belongs to format 2 (it needs the closing paren there).
    for _, sep in ipairs(smart_gf_config.separators) do
        if sep ~= "(" then
            local gap = sep == "," and "%s*" or "" -- file, line allows a space
            table.insert(patterns, '([^%s]+)' .. vim.pesc(sep) .. gap .. '(%d+)')
        end
    end

    return patterns
end

local smart_gf_patterns = build_smart_gf_patterns()

--- Resolve the file:line match that spans the cursor (strict). Patterns are
--- tried in priority order, each scanned left to right; a line with several
--- paths therefore resolves the one under the cursor, not the leftmost.
---@return string? path, string? linenr
local function resolve_at_cursor()
    local line = vim.api.nvim_get_current_line()
    local cursor_col = vim.api.nvim_win_get_cursor(0)[2]
    for _, pattern in ipairs(smart_gf_patterns) do
        local init = 1
        while true do
            local s, e, filepath, linenr = line:find(pattern, init)
            if not s then break end
            init = e + 1

            if cursor_col >= s - 1 and cursor_col <= e - 1 then
                for _, char in ipairs(smart_gf_config.trim_chars) do
                    filepath = filepath:gsub(vim.pesc(char), "")
                end
                filepath = filepath:gsub("^[%s%(%)%[%]{}%,%\"']+", ""):gsub("[%s%(%)%[%]{}%,%\"']+$", "")

                if vim.fn.filereadable(vim.fn.expand(filepath)) == 1 then
                    return filepath, linenr
                end
            end
        end
    end
end

--- Fallback for a bare file name under the cursor (no `:line`, so the
--- patterns above don't match): the `<cfile>` as-is when readable, else
--- searched recursively under cwd -- the same thing snacks' terminal gf did
--- (`findfile(name, "**")`).
---@return string? path
local function resolve_bare_cfile()
    local f = vim.fn.expand("<cfile>")
    if f == "" then return nil end
    if vim.fn.filereadable(f) == 1 then return f end
    local found = vim.fn.findfile(f, "**")
    if found ~= "" then return found end
end

--- Move the cursor of `win` to `lnum` and center it.
local function place_cursor(win, lnum)
    if not lnum then return end
    pcall(vim.api.nvim_win_set_cursor, win, { tonumber(lnum), 0 })
    vim.api.nvim_win_call(win, function() vim.cmd("normal! zz") end)
end

--- Open `path` (optionally at `lnum`) in `win` and focus it. Uses
--- `nvim_win_set_buf`, not `:edit`, so `switchbuf` can't redirect it to a
--- window that happens to show the file already.
local function open_in_window(win, path, lnum)
    local buf = vim.fn.bufadd(vim.fn.fnamemodify(path, ":p"))
    vim.fn.bufload(buf)
    vim.api.nvim_win_set_buf(win, buf)
    vim.api.nvim_set_current_win(win)
    place_cursor(win, lnum)
end

local function smart_gf(cmd)
    local path, linenr = resolve_at_cursor()

    -- Terminal: pick the target window with a letter in each one (ours --
    -- box/winpick.lua; snacks' pick_win excludes terminal windows and
    -- non-file buffers). The file under the cursor opens in the picked
    -- window; both `file:line` and bare names (`<cfile>`) resolve. Without
    -- any file the letter just focuses the window. Picking the terminal's
    -- own window replaces its view -- its job keeps running.
    if vim.bo.buftype == "terminal" then
        if not path then
            path = resolve_bare_cfile()
        end
        local win = require("box.winpick").pick()
        if not win then return end
        if path then
            open_in_window(win, path, linenr)
        else
            vim.api.nvim_set_current_win(win)
        end
        return
    end

    local function split_first()
        if cmd == "split" then
            vim.cmd("split")
        end
    end

    if path then
        split_first()
        vim.cmd("edit " .. vim.fn.fnameescape(path))
        place_cursor(0, linenr)
        return
    end

    -- Nothing file:line-like was under the cursor: fall back to built-in gF
    -- (gf + jump-to-line). Builtin gF never splits, so split explicitly first
    -- and roll it back if the file can't be found.
    split_first()
    local ok = pcall(function()
        vim.cmd("normal! gF")
    end)
    if not ok then
        if cmd == "split" then
            pcall(function() vim.cmd("close") end)
        end
        vim.notify("gf: can't find file - " .. vim.fn.expand("<cfile>"), vim.log.levels.WARN)
    end
end

function M.setup()
    --- Bind gf/gF, globally (`buf == nil`) or buffer-locally.
    ---@param buf? number
    local function bind(buf)
        vim.keymap.set("n", "gf", function() smart_gf("edit") end,
            { buffer = buf, noremap = true, silent = true, desc = "Smart gf (file:line)" })
        vim.keymap.set("n", "gF", function() smart_gf("split") end,
            { buffer = buf, noremap = true, silent = true, desc = "Smart gf (split)" })
    end
    bind()

    -- snacks terminals define their own buffer-local `gf` (findfile + hide +
    -- :e -- with `switchbuf=useopen` that jumps to an already-open window), so
    -- it shadows the global mapping above and the terminal branch never runs.
    -- Snacks re-applies its window keys on every show (win `_show` -> `map()`),
    -- so re-assert ours as buffer-local after each one; the schedule lands
    -- after snacks' synchronous re-map.
    vim.api.nvim_create_autocmd({ "FileType", "BufWinEnter" }, {
        callback = function(args)
            local buf = args.buf
            if vim.bo[buf].filetype ~= "snacks_terminal" then return end
            vim.schedule(function()
                if vim.api.nvim_buf_is_valid(buf) then bind(buf) end
            end)
        end,
    })
end

return M
