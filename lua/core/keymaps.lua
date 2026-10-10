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

-- <C-v> pastes the clipboard literally and fixes the indent, as its own undo
-- step (i_CTRL-R_CTRL-P + i_CTRL-G_u). Trade-off: loses built-in literal-insert
-- (<C-q> still does that). GUI/Neovide only — Windows Terminal eats Ctrl+V.
map("i", "<C-v>", "<C-g>u<C-r><C-p>+", d("Paste from clipboard (fix indent)"))

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


-- Command mode editing. No <silent>: a silent map sets cmd_silent while its
-- RHS runs, which makes putcmdline()/redrawcmd() early-return, so the pasted
-- text is in cmdbuff but no cmdline_show is emitted until the next key.
local cd = function(desc)
    return vim.tbl_extend("force", { noremap = true }, { desc = desc })
end
map("c", "<C-a>", "<Home>", cd("Cmdline: line start"))
map("c", "<C-e>", "<End>", cd("Cmdline: line end"))
map("c", "<C-b>", "<Left>", cd("Cmdline: left one char"))
map("c", "<C-f>", "<Right>", cd("Cmdline: right one char"))
map("c", "<m-b>", "<C-Left>", cd("Cmdline: left one word"))
map("c", "<m-f>", "<C-Right>", cd("Cmdline: right one word"))
map("c", "<C-d>", "<Del>", cd("Cmdline: delete char"))
-- literal paste from the clipboard (note: in cmdline <C-r><C-p> means "filename
-- under the cursor", not the insert-mode literal+fix-indent behavior)
map("c", "<C-v>", "<C-r><C-o>+", cd("Cmdline: paste from clipboard (literal)"))
map("c", "<C-j>", "<down>", cd("Cmdline: history down"))
map("c", "<C-k>", "<up>", cd("Cmdline: history up"))

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

map("n", "<leader>wp", "<C-w>p", d("Previous window"))
