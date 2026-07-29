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
            pcall(vim.cmd, 'normal! g`"zzzv')
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

local root_markers = require("config.root_markers")

local auto_cwd_aug = augroup("auto_cwd", { clear = true })
local cwd_cache = {}
autocmd("BufEnter", {
    group = auto_cwd_aug,
    callback = function()
        local path = vim.api.nvim_buf_get_name(0)
        if path == "" or vim.bo.buftype ~= "" then
            return
        end
        if vim.bo.filetype == "oil" then
            return
        end
        local dir = vim.fs.dirname(path)
        if cwd_cache[dir] == nil then
            cwd_cache[dir] = vim.fs.root(0, root_markers) or dir
        end
        local target = cwd_cache[dir]
        if vim.fn.getcwd() ~= target then
            vim.fn.chdir(target)
        end
    end,
})

-- SOS source control commands
vim.api.nvim_create_user_command("Sco", "exec '!soscmd6 co %'", {})
vim.api.nvim_create_user_command("Scon", "exec '!soscmd6 co -Nlock %'", {})
vim.api.nvim_create_user_command("Sci", "exec '!soscmd6 ci %'", {})
vim.api.nvim_create_user_command("Scim", function(opts)
    local file = vim.fn.expand("%")
    vim.system({ "soscmd6", "ci", "-achange_summary=" .. opts.args, file })
end, { nargs = 1 })
vim.api.nvim_create_user_command("Sd", "exec '!soscmd6 discard %'", {})
vim.api.nvim_create_user_command("Sdf", "exec '!soscmd6 discard -F %'", {})
vim.api.nvim_create_user_command("Sup", "exec '!soscmd6 update'", {})
vim.api.nvim_create_user_command("Scr", "exec '!soscmd6 create %'", {})

-- Other commands
vim.api.nvim_create_user_command("Tgen", function(opts)
    vim.cmd("exec '!tempgen.py -f % -t " .. opts.args .. "'")
end, { nargs = 1 })
vim.api.nvim_create_user_command("Rm", "exec '!run_mako.py'", {})
vim.api.nvim_create_user_command("Fp", "exec '!gen_func_prototype.py -s % -p %:h'", {})
