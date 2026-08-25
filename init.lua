vim.loader.enable()

local uname = vim.uv.os_uname()
local os_name = uname.sysname
if os_name == "Windows_NT" then
    vim.g.os = "windows"
    if not os.getenv("HOME") then
        vim.env.HOME = os.getenv("USERPROFILE")
    end
elseif os_name == "Darwin" then
    vim.g.os = "macos"
else
    vim.g.os = "linux"
end

-- RHEL6 detection: kernel 2.6.32 or glibc < 2.18. Some settings only apply on
-- the RHEL6 box (e.g. blink.cmp fuzzy must use the Lua implementation because
-- the prebuilt Rust lib requires glibc >= 2.18).
vim.g.is_rhel6 = false
vim.g.glibc_version = ""
if vim.g.os == "linux" then
    local release = (uname.release or ""):lower()
    vim.g.glibc_version = vim.fn.system("ldd --version 2>/dev/null | head -1"):match("(%d+%.%d+)") or ""
    local gv = tonumber(vim.g.glibc_version) or 99
    vim.g.is_rhel6 = release:match("^2%.6%.32") ~= nil or (vim.g.glibc_version ~= "" and gv < 2.18)
end

vim.g.data_dir = vim.fn.stdpath("data") .. "/"

vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

if vim.g.os == "windows" then
    vim.g.clipboard = {
        name = "win32yank",
        copy = { ["+"] = "win32yank.exe -i --crlf", ["*"] = "win32yank.exe -i --crlf" },
        paste = { ["+"] = "win32yank.exe -o --lf", ["*"] = "win32yank.exe -o --lf" },
        cache_enabled = 0,
    }
elseif vim.g.os == "macos" then
    vim.g.clipboard = {
        name = "macos",
        copy = { ["+"] = "pbcopy", ["*"] = "pbcopy" },
        paste = { ["+"] = "pbpaste", ["*"] = "pbpaste" },
        cache_enabled = 0,
    }
-- elseif vim.fn.executable("xclip") == 1 then
--     vim.g.clipboard = {
--         name = "xclip",
--         copy = { ["+"] = "xclip -selection clipboard", ["*"] = "xclip -selection primary" },
--         paste = { ["+"] = "xclip -selection clipboard -o", ["*"] = "xclip -selection primary -o" },
--         cache_enabled = 0,
--     }
-- elseif vim.fn.executable("xsel") == 1 then
--     vim.g.clipboard = {
--         name = "xsel",
--         copy = { ["+"] = "xsel --clipboard --input", ["*"] = "xsel --primary --input" },
--         paste = { ["+"] = "xsel --clipboard --output", ["*"] = "xsel --primary --output" },
--         cache_enabled = 0,
--     }
end

if vim.g.os == "windows" then
    vim.env.HTTP_PROXY = "http://127.0.0.1:7897"
    vim.env.HTTPS_PROXY = "http://127.0.0.1:7897"
    vim.env.http_proxy = "http://127.0.0.1:7897"
    vim.env.https_proxy = "http://127.0.0.1:7897"
    vim.env.PATH = vim.fn.expand("~/AppData/Local/LuaRocks") .. ";" .. vim.fn.expand("~/AppData/Local/LuaRocks/bin") .. ";" .. vim.env.PATH
end

require("core.options")
require("core.keymaps")
require("core.autocmds")
require("config.project")

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath .. "/lua/lazy/init.lua") then
    if vim.uv.fs_stat(lazypath) then
        if vim.g.os == "windows" then
            vim.fn.system({ "rmdir", "/s", "/q", lazypath })
        else
            vim.fn.system({ "rm", "-rf", lazypath })
        end
    end
    local lazyrepo = "https://github.com/folke/lazy.nvim.git"
    local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
    if vim.v.shell_error ~= 0 then
        vim.api.nvim_echo({
            { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
            { out, "WarningMsg" },
            { "\nPress any key to exit...", "MoreMsg" },
        }, true, {})
        vim.fn.getchar()
        vim.cmd.quit()
    end
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
    spec = {
        { import = "plugins" },
    },
    defaults = { lazy = true, version = false },
    install = { colorscheme = { "habamax" } },
    checker = { enabled = false, notify = false },
    change_detection = { notify = false },
    rocks = {
        hererocks = true,
    },
    performance = {
        cache = { enabled = true },
        reset_packpath = true,
    },
})

require("config.lsp").setup()

require("util.tools")
