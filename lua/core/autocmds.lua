vim.filetype.add({
    extension = {
        v = "systemverilog",
        vh = "systemverilog",
        sv = "systemverilog",
        svh = "systemverilog",
        svi = "systemverilog",
        log = "log",
        tc = "tc",
        ralf = "ralf",
    },
})

local augroup = vim.api.nvim_create_augroup
local autocmd = vim.api.nvim_create_autocmd

local return_pos = augroup("return_exit_position", { clear = true })
autocmd("BufReadPost", {
    group = return_pos,
    callback = function()
        local mark = vim.api.nvim_buf_get_mark(0, '"')
        local lcount = vim.fn.line("$")
        if mark[1] > 1 and mark[1] <= lcount then
            pcall(function() vim.cmd('normal! g`"zzzv') end)
        end
    end,
})

--[[
local update_last_modified = augroup("update_last_modified_on_write", { clear = true })
autocmd("BufWritePre", {
    group = update_last_modified,
    callback = function()
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        for i, line in ipairs(lines) do
            if line:find("Last Modified") or line:find("Last modified") then
                local time = vim.fn.strftime("%Y-%m-%d %H:%M:%S")
                local cs = vim.bo.commentstring
                if cs == "" then cs = "# %s" end
                local newline = cs:gsub("%%s", "Last Modified: " .. time)
                vim.fn.setline(i, newline)
                break
            end
        end
    end,
})
--]]

local nonumber = augroup("nonumber_group", { clear = true })
autocmd("FileType", {
    group = nonumber,
    pattern = { "help", "git", "gitcommit" },
    callback = function()
        vim.opt_local.number = false
        vim.opt_local.relativenumber = false
        vim.opt_local.signcolumn = "no"
    end,
})

local nolist = augroup("nolist_group", { clear = true })
autocmd("FileType", {
    group = nolist,
    pattern = { "help", "git", "gitcommit", "log", "text" },
    callback = function()
        vim.opt_local.list = false
    end,
})

local q_help = augroup("q_for_quit_on_help", { clear = true })
autocmd("FileType", {
    group = q_help,
    pattern = "help",
    callback = function()
        vim.keymap.set("n", "q", ":bwipeout<CR>", { buffer = true, silent = true, desc = "Close help buffer" })
    end,
})
