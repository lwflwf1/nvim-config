-- Smart gf/gF: open the file:line path under the cursor (quoted, file(line),
-- file:line, file;line, ...), falling back to the built-in gf/gF. setup()
-- registers the two normal-mode maps.
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

-- Build the match patterns from the config
local function build_smart_gf_patterns()
    local patterns = {}

    -- 1. Quoted formats: "file", line or 'file', line
    for _, q in ipairs(smart_gf_config.quote_chars) do
        local q_esc = vim.pesc(q)
        table.insert(patterns, {
            q_esc .. '([^' .. q_esc .. ']+)' .. q_esc .. ',?%s*(%d+)',
            1, 2,
        })
    end

    -- 2. file(line) format (UVM logs, compiler errors) — before :/;/,
    --    because a line like "path.sv(256) @ 123ns: ... for ctl_id:0" must
    --    match the file(256) part, not the later word:number (e.g. ctl_id:0).
    for _, sep in ipairs(smart_gf_config.separators) do
        if sep == "(" then
            table.insert(patterns, { '([^%s]+)%((%d+)%)', 1, 2 })
        end
    end

    -- 3. Unquoted formats with a separator: file:line, file;line, file, line
    for _, sep in ipairs(smart_gf_config.separators) do
        local sep_esc = vim.pesc(sep)
        if sep == ":" then
            -- file:line
            table.insert(patterns, { '([^%s]+)' .. sep_esc .. '(%d+)', 1, 2 })
        elseif sep == "," then
            -- file, line (optional space after the comma)
            table.insert(patterns, { '([^%s]+)' .. sep_esc .. '%s*(%d+)', 1, 2 })
        else
            -- file;line etc.
            table.insert(patterns, { '([^%s]+)' .. sep_esc .. '(%d+)', 1, 2 })
        end
    end

    return patterns
end

local smart_gf_patterns = build_smart_gf_patterns()

local function smart_gf(cmd)
    local line = vim.api.nvim_get_current_line()
    local cursor_col = vim.api.nvim_win_get_cursor(0)[2]

    -- Open the file:line match that spans the cursor (strict). Patterns are
    -- tried in priority order, each scanned left to right; a line with several
    -- paths therefore opens the one under the cursor, not the leftmost. If
    -- nothing file:line-like is under the cursor, fall back to built-in gf/gF
    -- (handles bare filenames without a line number).
    for _, pattern_info in ipairs(smart_gf_patterns) do
        local pattern = pattern_info[1]
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
                    if cmd == "split" then
                        vim.cmd("split")
                    end
                    vim.cmd("edit " .. vim.fn.fnameescape(filepath))
                    vim.api.nvim_win_set_cursor(0, { tonumber(linenr), 0 })
                    vim.cmd("normal! zz")
                    return
                end
            end
        end
    end

    -- Nothing file:line-like was under the cursor: fall back to built-in gF
    -- (gf + jump-to-line). Builtin gF never splits, so split explicitly first
    -- and roll it back if the file can't be found.
    if cmd == "split" then
        vim.cmd("split")
    end
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
    local map = function(lhs, rhs, desc)
        vim.keymap.set("n", lhs, rhs, { noremap = true, silent = true, desc = desc })
    end
    map("gf", function() smart_gf("edit") end, "Smart gf (file:line)")
    map("gF", function() smart_gf("split") end, "Smart gf (split)")
end

return M
