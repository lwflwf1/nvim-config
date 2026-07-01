local map = vim.keymap.set
local opts = { noremap = true, silent = true }

vim.g.mapleader = " "
vim.g.maplocalleader = " "

map("n", "H", "^", opts)
map("n", "L", "$", opts)
map({ "n", "v" }, "j", "gj", opts)
map({ "n", "v" }, "k", "gk", opts)

map({ "n", "i", "t" }, "<M-h>", "<C-w>h", opts)
map({ "n", "i", "t" }, "<M-j>", "<C-w>j", opts)
map({ "n", "i", "t" }, "<M-k>", "<C-w>k", opts)
map({ "n", "i", "t" }, "<M-l>", "<C-w>l", opts)

map("n", "<C-h>", ":bprevious<CR>", opts)
map("n", "<C-l>", ":bnext<CR>", opts)
map("n", "<leader>bd", ":bdelete<CR>", vim.tbl_extend("force", opts, { desc = "Close buffer" }))

map("n", "<", "<<", opts)
map("n", ">", ">>", opts)
map("v", "<", "<gv", opts)
map("v", ">", ">gv", opts)

map("i", "jj", "<Esc>", opts)
map("i", "<C-a>", "<Home>", opts)
map("i", "<C-e>", "<End>", opts)
map("i", "<C-b>", "<Left>", opts)
map("i", "<C-f>", "<Right>", opts)
map("i", "<C-d>", "<Del>", opts)

map("n", "<leader>qn", ":cnext<CR>", vim.tbl_extend("force", opts, { desc = "Next quickfix" }))
map("n", "<leader>qp", ":cprevious<CR>", vim.tbl_extend("force", opts, { desc = "Prev quickfix" }))
map("n", "<leader>ql", ":copen<CR>", vim.tbl_extend("force", opts, { desc = "Open quickfix" }))

map("i", "<M-i>", "<C-]>", opts)
map("n", "<M-i>", "g;", opts)

map("n", "<UP>", ":res +5<CR>", opts)
map("n", "<DOWN>", ":res -5<CR>", opts)
map("n", "<LEFT>", ":vertical res +5<CR>", opts)
map("n", "<RIGHT>", ":vertical res -5<CR>", opts)

-- Window management
map("n", "<leader>wo", "<C-w>o", vim.tbl_extend("force", opts, { desc = "Close other windows" }))
map("n", "<leader>wr", "<C-w>R", vim.tbl_extend("force", opts, { desc = "Rotate windows" }))
map("n", "<leader>wx", "<C-w>x", vim.tbl_extend("force", opts, { desc = "Swap windows" }))
map("n", "<leader>w=", "<C-w>=", vim.tbl_extend("force", opts, { desc = "Equal windows" }))
map("n", "<leader>wT", "<C-w>T", vim.tbl_extend("force", opts, { desc = "Move to new tab" }))
map("n", "<leader>w]", "<C-w>]", vim.tbl_extend("force", opts, { desc = "Split tag" }))
map("n", "<leader>wd", "<C-w>d", vim.tbl_extend("force", opts, { desc = "Split definition" }))
map("n", "<leader>wf", "<C-w>f", vim.tbl_extend("force", opts, { desc = "Split file" }))
map("n", "<leader>wi", "<C-w>i", vim.tbl_extend("force", opts, { desc = "Split include" }))
map("n", "<leader>wF", "<C-w>gF", vim.tbl_extend("force", opts, { desc = "Split file:line" }))
map("n", "<leader>wp", "<C-w>p", vim.tbl_extend("force", opts, { desc = "Previous window" }))
map("n", "<leader>wq", "<C-w>q", vim.tbl_extend("force", opts, { desc = "Close window" }))
map("n", "<leader>wH", ":<C-u>topleft vsplit<CR>", vim.tbl_extend("force", opts, { desc = "Split left (topleft)" }))
map("n", "<leader>wL", ":<C-u>botright vsplit<CR>", vim.tbl_extend("force", opts, { desc = "Split right (botright)" }))
map("n", "<leader>wJ", ":<C-u>botright split<CR>", vim.tbl_extend("force", opts, { desc = "Split below (botright)" }))
map("n", "<leader>wK", ":<C-u>topleft split<CR>", vim.tbl_extend("force", opts, { desc = "Split above (topleft)" }))
map("n", "<leader>wh", ":<C-u>leftabove vsplit<CR>", vim.tbl_extend("force", opts, { desc = "Split left" }))
map("n", "<leader>wl", ":<C-u>rightbelow vsplit<CR>", vim.tbl_extend("force", opts, { desc = "Split right" }))
map("n", "<leader>wk", ":<C-u>leftabove split<CR>", vim.tbl_extend("force", opts, { desc = "Split above" }))
map("n", "<leader>wj", ":<C-u>rightbelow split<CR>", vim.tbl_extend("force", opts, { desc = "Split below" }))


-- Command mode editing
map("c", "<C-a>", "<Home>", opts)
map("c", "<C-e>", "<End>", opts)
map("c", "<C-b>", "<Left>", opts)
map("c", "<C-f>", "<Right>", opts)
map("c", "<m-b>", "<C-Left>", opts)
map("c", "<m-f>", "<C-Right>", opts)
map("c", "<C-d>", "<Del>", opts)
map("c", "<c-y>", '<C-r>"', opts)
map("c", "<C-j>", "<down>", opts)
map("c", "<C-k>", "<up>", opts)

-- Text objects for brackets/quotes
map("o", "inb", [[:<C-u>silent execute "normal! /(\r:nohlsearch\rvi("<CR>]], opts)
map("o", "ilb", [[:<C-u>silent execute "normal! ?(\r:nohlsearch\rvi("<CR>]], opts)
map("o", "in[", [[:<C-u>silent execute "normal! /[\r:nohlsearch\rvi["<CR>]], opts)
map("o", "il[", [[:<C-u>silent execute "normal! ?[\r:nohlsearch\rvi["<CR>]], opts)
map("o", "in]", [[:<C-u>silent execute "normal! /[\r:nohlsearch\rvi["<CR>]], opts)
map("o", "il]", [[:<C-u>silent execute "normal! ?[\r:nohlsearch\rvi["<CR>]], opts)
map("o", "in{", [[:<C-u>silent execute "normal! /{\r:nohlsearch\rvi{"<CR>]], opts)
map("o", "il{", [[:<C-u>silent execute "normal! ?{\r:nohlsearch\rvi{"<CR>]], opts)
map("o", "in}", [[:<C-u>silent execute "normal! /{\r:nohlsearch\rvi{"<CR>]], opts)
map("o", "il}", [[:<C-u>silent execute "normal! ?{\r:nohlsearch\rvi{"<CR>]], opts)
map("o", 'in"', [[:<C-u>silent execute "normal! /\"\r:nohlsearch\rvi\"" <CR>]], opts)
map("o", 'il"', [[:<C-u>silent execute "normal! ?\"\r:nohlsearch\rvi\"" <CR>]], opts)
map("o", "in'", [[:<C-u>silent execute "normal! /'\r:nohlsearch\rvi'"<CR>]], opts)
map("o", "il'", [[:<C-u>silent execute "normal! ?'\r:nohlsearch\rvi'"<CR>]], opts)

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
