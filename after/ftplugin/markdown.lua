local map = vim.keymap.set

map("i", "<M-1>", "#<space>", { buffer = true })
map("i", "<M-2>", "##<space>", { buffer = true })
map("i", "<M-3>", "###<space>", { buffer = true })
map("i", "<M-4>", "####<space>", { buffer = true })
map("i", "<M-5>", "#####<space>", { buffer = true })
map("i", "<M-6>", "######<space>", { buffer = true })
map("i", "<M-b>", "**** <++><esc>7ha", { buffer = true })
map("i", "<M-`>", "`` <++><esc>6ha", { buffer = true })
map("i", "<M-c>", "```<cr>```<cr><++><esc>2kA", { buffer = true })
map("i", "<M-p>", "![](<++>)<cr><++><esc>k$7ha", { buffer = true })
map("i", "<M-u>", "[](<++>)<cr><++><esc>k$7ha", { buffer = true })
