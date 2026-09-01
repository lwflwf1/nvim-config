local map = vim.keymap.set
local opts = { noremap = true, silent = true }
local d = function(desc) return vim.tbl_extend("force", opts, { desc = desc }) end

vim.g.mapleader = " "
vim.g.maplocalleader = " "

map({ "n", "v", "o" }, "H", "^", d("Go to first non-blank"))
map({ "n", "v", "o" }, "L", "$", d("Go to end of line"))
map({ "n", "v" }, "j", "gj", d("Down (display lines)"))
map({ "n", "v" }, "k", "gk", d("Up (display lines)"))

map("n", "<C-h>", function()
    local ok, bl = pcall(require, "bufferline")
    if ok then
        for _ = 1, vim.v.count1 do bl.cycle(-1) end
    else
        vim.cmd("bprevious")
    end
end, d("Previous buffer"))
map("n", "<C-l>", function()
    local ok, bl = pcall(require, "bufferline")
    if ok then
        for _ = 1, vim.v.count1 do bl.cycle(1) end
    else
        vim.cmd("bnext")
    end
end, d("Next buffer"))

map("n", "<", "<<", d("Indent left"))
map("n", ">", ">>", d("Indent right"))
map("v", "<", "<gv", d("Indent left (keep selection)"))
map("v", ">", ">gv", d("Indent right (keep selection)"))

map("i", "<C-a>", "<Home>", d("Line start"))
map("i", "<C-e>", "<End>", d("Line end"))
map("i", "<C-b>", "<Left>", d("Left one char"))
map("i", "<C-f>", "<Right>", d("Right one char"))
map("i", "<C-d>", "<Del>", d("Delete char"))

map("n", "<leader>qn", ":cnext<CR>", vim.tbl_extend("force", opts, { desc = "Next quickfix" }))
map("n", "<leader>qp", ":cprevious<CR>", vim.tbl_extend("force", opts, { desc = "Prev quickfix" }))

map("i", "<M-i>", "<C-]>", d("Jump to tag"))
map("n", "<M-i>", "g;", d("Jump to last change"))

-- Window management
map("n", "<leader>wo", "<C-w>o", vim.tbl_extend("force", opts, { desc = "Close other windows" }))
map("n", "<leader>wr", "<C-w>R", vim.tbl_extend("force", opts, { desc = "Rotate windows" }))
map("n", "<leader>wx", "<C-w>x", vim.tbl_extend("force", opts, { desc = "Swap windows" }))
map("n", "<leader>w=", "<C-w>=", vim.tbl_extend("force", opts, { desc = "Equal windows" }))
map("n", "<leader>wt", "<C-w>T", vim.tbl_extend("force", opts, { desc = "Move to new tab" }))
map("n", "<leader>wH", ":<C-u>topleft vsplit<CR>", vim.tbl_extend("force", opts, { desc = "Split left (topleft)" }))
map("n", "<leader>wL", ":<C-u>botright vsplit<CR>", vim.tbl_extend("force", opts, { desc = "Split right (botright)" }))
map("n", "<leader>wJ", ":<C-u>botright split<CR>", vim.tbl_extend("force", opts, { desc = "Split below (botright)" }))
map("n", "<leader>wK", ":<C-u>topleft split<CR>", vim.tbl_extend("force", opts, { desc = "Split above (topleft)" }))
map("n", "<leader>wh", ":<C-u>leftabove vsplit<CR>", vim.tbl_extend("force", opts, { desc = "Split left" }))
map("n", "<leader>wl", ":<C-u>rightbelow vsplit<CR>", vim.tbl_extend("force", opts, { desc = "Split right" }))
map("n", "<leader>wk", ":<C-u>leftabove split<CR>", vim.tbl_extend("force", opts, { desc = "Split above" }))
map("n", "<leader>wj", ":<C-u>rightbelow split<CR>", vim.tbl_extend("force", opts, { desc = "Split below" }))


-- Command mode editing
map("c", "<C-a>", "<Home>", d("Cmdline: line start"))
map("c", "<C-e>", "<End>", d("Cmdline: line end"))
map("c", "<C-b>", "<Left>", d("Cmdline: left one char"))
map("c", "<C-f>", "<Right>", d("Cmdline: right one char"))
map("c", "<m-b>", "<C-Left>", d("Cmdline: left one word"))
map("c", "<m-f>", "<C-Right>", d("Cmdline: right one word"))
map("c", "<C-d>", "<Del>", d("Cmdline: delete char"))
map("c", "<c-y>", '<C-r>"', d("Cmdline: paste register"))
map("c", "<C-j>", "<down>", d("Cmdline: history down"))
map("c", "<C-k>", "<up>", d("Cmdline: history up"))

-- Text objects for brackets/quotes
map("o", "inb", [[:<C-u>silent execute "normal! /(\r:nohlsearch\rvi("<CR>]], d("Inside next ()"))
map("o", "ilb", [[:<C-u>silent execute "normal! ?(\r:nohlsearch\rvi("<CR>]], d("Inside last ()"))
map("o", "in[", [[:<C-u>silent execute "normal! /[\r:nohlsearch\rvi["<CR>]], d("Inside next []"))
map("o", "il[", [[:<C-u>silent execute "normal! ?[\r:nohlsearch\rvi["<CR>]], d("Inside last []"))
map("o", "in]", [[:<C-u>silent execute "normal! /[\r:nohlsearch\rvi["<CR>]], d("Inside next []"))
map("o", "il]", [[:<C-u>silent execute "normal! ?[\r:nohlsearch\rvi["<CR>]], d("Inside last []"))
map("o", "in{", [[:<C-u>silent execute "normal! /{\r:nohlsearch\rvi{"<CR>]], d("Inside next {}"))
map("o", "il{", [[:<C-u>silent execute "normal! ?{\r:nohlsearch\rvi{"<CR>]], d("Inside last {}"))
map("o", "in}", [[:<C-u>silent execute "normal! /{\r:nohlsearch\rvi{"<CR>]], d("Inside next {}"))
map("o", "il}", [[:<C-u>silent execute "normal! ?{\r:nohlsearch\rvi{"<CR>]], d("Inside last {}"))
map("o", 'in"', [[:<C-u>silent execute "normal! /\"\r:nohlsearch\rvi\"" <CR>]], d('Inside next ""'))
map("o", 'il"', [[:<C-u>silent execute "normal! ?\"\r:nohlsearch\rvi\"" <CR>]], d('Inside last ""'))
map("o", "in'", [[:<C-u>silent execute "normal! /'\r:nohlsearch\rvi'"<CR>]], d("Inside next ''"))
map("o", "il'", [[:<C-u>silent execute "normal! ?'\r:nohlsearch\rvi'"<CR>]], d("Inside last ''"))

-- Tab management
map("n", "<leader>te", ":<C-u>tabnew<CR>", vim.tbl_extend("force", opts, { desc = "New tab" }))
map("n", "<leader>tc", ":<C-u>tabclose<CR>", vim.tbl_extend("force", opts, { desc = "Close tab" }))
map("n", "<leader>to", ":<C-u>tabonly<CR>", vim.tbl_extend("force", opts, { desc = "Close other tabs" }))
map("n", "<leader>tm", ":<C-u>tabmove<CR>", vim.tbl_extend("force", opts, { desc = "Move tab" }))
map("n", "<Tab>", ":<C-u>tabnext<CR>", vim.tbl_extend("force", opts, { desc = "Next tab" }))
map("n", "<S-Tab>", ":<C-u>tabprevious<CR>", vim.tbl_extend("force", opts, { desc = "Previous tab" }))

-- SOS source control shortcuts
-- map("n", "<leader>so", ":Sco<CR>", vim.tbl_extend("force", opts, { desc = "SOS checkout" }))
map("n", "<leader>so", ":Scon<CR>", vim.tbl_extend("force", opts, { desc = "SOS checkout (Nlock)" }))
map("n", "<leader>si", ":Sci<CR>", vim.tbl_extend("force", opts, { desc = "SOS checkin" }))
map("n", "<leader>sI", function()
    local msg = vim.fn.input("Change summary: ")
    if msg ~= "" then
        vim.cmd("Scim " .. msg)
    end
end, vim.tbl_extend("force", opts, { desc = "SOS checkin with message" }))
map("n", "<leader>sd", ":Sd<CR>", vim.tbl_extend("force", opts, { desc = "SOS discard" }))
map("n", "<leader>sD", ":Sdf<CR>", vim.tbl_extend("force", opts, { desc = "SOS discard -F" }))
map("n", "<leader>su", ":Sup<CR>", vim.tbl_extend("force", opts, { desc = "SOS update" }))
map("n", "<leader>sr", ":Scr<CR>", vim.tbl_extend("force", opts, { desc = "SOS create" }))

-- Toggle value under cursor
local toggle_dict = {
    { "&", "|" },
    { "~", "!" },
    { "always_ff", "always_latch", "always_comb" },
    { "posedge", "negedge" },
    { "logic", "bit" },
    { "@", "wait" },
    { " <=", " =" },
    { "input", "output", "ref" },
    { "'b", "'h", "'d" },
    { "endfunction", "endtask", "endclass", "endinterface", "endmodule", "end", "endclocking" },
    { "function", "task" },
    { "WRITE", "READ" },
}

local function toggle_value()
    local word = vim.fn.expand("<cword>")
    for _, group in ipairs(toggle_dict) do
        for i, v in ipairs(group) do
            if word == v then
                local next = group[i % #group + 1]
                vim.cmd("normal! ciw" .. next)
                return
            end
        end
    end
end

map("n", "<leader>sw", toggle_value, vim.tbl_extend("force", opts, { desc = "Toggle value" }))

-- Smart GF: open file and jump to line
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

    for _, pattern_info in ipairs(smart_gf_patterns) do
        local pattern, filepath_group, line_group = pattern_info[1], pattern_info[2], pattern_info[3]
        local filepath, linenr = line:match(pattern)

        if filepath and linenr then
            for _, char in ipairs(smart_gf_config.trim_chars) do
                filepath = filepath:gsub(vim.pesc(char), "")
            end

            filepath = filepath:gsub("^[%s%(%)%[%]{}%,%\"']+", ""):gsub("[%s%(%)%[%]{}%,%\"']+$", "")

            local expanded = vim.fn.expand(filepath)
            -- Keep trying the next pattern when this candidate does not
            -- resolve to a real file (e.g. "ctl_id:0" inside a UVM log line
            -- must not shadow the earlier "path.sv(256)" match).
            if vim.fn.filereadable(expanded) == 0 then
                goto continue
            end

            if cmd == "split" then
                vim.cmd("split")
            end
            vim.cmd("edit " .. vim.fn.fnameescape(filepath))
            vim.api.nvim_win_set_cursor(0, { tonumber(linenr), 0 })
            vim.cmd("normal! zz")
            return
        end

        ::continue::
    end

    local ok = pcall(vim.cmd, "normal! " .. (cmd == "split" and "gF" or "gf"))
    if not ok then
        vim.notify("gf: can't find file - " .. vim.fn.expand("<cfile>"), vim.log.levels.WARN)
    end
end

map("n", "gf", function() smart_gf("edit") end, vim.tbl_extend("force", opts, { desc = "Smart gf (file:line)" }))
map("n", "gF", function() smart_gf("split") end, vim.tbl_extend("force", opts, { desc = "Smart gf (split)" }))

map("i", "<M-;>", function()
    local chars = {}
    for _, info in pairs(require("mini.pairs").config.mappings) do
        chars[vim.fn.strcharpart(info.pair, 1, 1)] = true
    end
    local line = vim.api.nvim_get_current_line()
    local col = vim.api.nvim_win_get_cursor(0)[2] + 1
    local rest = line:sub(col)
    local min_pos
    for c in pairs(chars) do
        local p = rest:find(vim.pesc(c))
        if p and (not min_pos or p < min_pos) then min_pos = p end
    end
    if min_pos then
        vim.api.nvim_feedkeys(
            vim.api.nvim_replace_termcodes(string.rep("<Right>", min_pos), true, false, true),
            "n", false
        )
    end
end, d("Jump to next closing bracket/quote"))
