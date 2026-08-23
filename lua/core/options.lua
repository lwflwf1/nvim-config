local opt = vim.opt

opt.diffopt = "vertical,filler,internal,context:4"
opt.fileformat = "unix"
opt.fileformats = "unix"

vim.api.nvim_create_autocmd("BufWritePre", {
  pattern = "*",
  callback = function()
    vim.opt_local.fileformat = "unix"
  end,
})
opt.termguicolors = true

opt.autoindent = true
opt.smartindent = true
opt.mouse = "a"
opt.number = true
opt.relativenumber = true
opt.wildmenu = true
opt.showcmd = true
opt.hlsearch = true
opt.incsearch = true
opt.wrapscan = true
opt.ignorecase = true
opt.smartcase = true
opt.infercase = true
opt.fileencodings = "utf-8,gbk,ucs-bom"
opt.expandtab = true
opt.smarttab = true
opt.tabstop = 4
opt.shiftwidth = 4
opt.softtabstop = 4
opt.shiftround = true
opt.list = true
-- ASCII-only listchars: the terminal renders Nerd Font PUA glyphs at 2 cells,
-- so ambiwidth=double (below) is required to keep nvim's width math aligned;
-- ambiguous-width chars in listchars would then fail with E834.
opt.listchars = "tab:> ,trail:-,extends:>,precedes:<"
opt.ambiwidth = "double"

opt.foldenable = true
opt.foldlevelstart = 99
opt.laststatus = 3
opt.wrap = false
opt.linebreak = true
opt.clipboard:append("unnamedplus")
opt.scrolloff = 3
opt.sidescrolloff = 5
opt.completeopt = "menu,menuone,noselect"
opt.pumheight = 15
opt.shortmess:append("c")
opt.hidden = true
opt.updatetime = 100
opt.showtabline = 2
opt.autoread = true
opt.undofile = true
opt.backup = false
opt.swapfile = false
opt.conceallevel = 2
opt.concealcursor = "nc"
opt.backspace = "indent,eol,start"
opt.nrformats = "bin,hex,alpha"
opt.timeoutlen = 700
opt.ttimeoutlen = 50
opt.virtualedit = "block"
opt.synmaxcol = 2500
opt.textwidth = 0
opt.splitbelow = true
opt.splitright = true
opt.switchbuf = "useopen"
opt.winwidth = 30
opt.winminwidth = 10
opt.confirm = true
opt.errorbells = false
opt.matchpairs:append("<:>")
opt.timeout = true
opt.ttimeout = true
opt.sessionoptions:remove("blank")
opt.sessionoptions:remove("options")
opt.sessionoptions:append("unix")
opt.startofline = false

if vim.g.os == "windows" then
    opt.winaltkeys = "no"
    opt.shell = "powershell"
    opt.shellcmdflag = "-NoLogo -NoProfile -ExecutionPolicy RemoteSigned -Command"
    opt.shellxquote = ""
elseif vim.g.os == "macos" then
    opt.shell = "zsh"
else
    local user_shell = vim.env.SHELL
    if user_shell and vim.fn.executable(user_shell) == 1 then
        opt.shell = user_shell
    else
        opt.shell = "bash"
    end
end

opt.fillchars:append("eob: ")
opt.inccommand = "nosplit"
opt.signcolumn = "yes:2"

if vim.fn.executable("rg") == 1 then
    opt.grepformat = "%f:%l:%m"
    opt.grepprg = "rg --vimgrep" .. (opt.smartcase:get() and " --smart-case" or "")
end

local data_dir = vim.g.data_dir
local dirs = {
    backup = data_dir .. "backup",
    undo = data_dir .. "undo",
    swap = data_dir .. "swap",
    view = data_dir .. "view",
}
for _, dir in pairs(dirs) do
    vim.fn.mkdir(dir, "p")
end
opt.undodir = dirs.undo
opt.directory = dirs.swap
opt.backupdir = dirs.backup
opt.viewdir = dirs.view

local suffixes = ".bak,~,.o,.h,.info,.swp,.obj,.pyc,.pyo,.egg-info,.class"
opt.suffixes = suffixes

local ignore = {
    "*.o", "*.obj", "*~", "*.exe", "*.a", "*.pdb", "*.lib",
    "*.so", "*.dll", "*.swp", "*.egg", "*.jar", "*.class", "*.pyc", "*.pyo", "*.dex",
    "*.zip", "*.7z", "*.rar", "*.gz", "*.tar", "*.gzip", "*.bz2", "*.tgz", "*.xz",
    "*DS_Store*", "*.ipch", "*.gem",
    "*.png", "*.jpg", "*.gif", "*.bmp", "*.tga", "*.pcx", "*.ppm", "*.img", "*.iso",
    "*/.Trash/**", "*.pdf", "*.dmg", "*/.rbenv/**",
    "*/.nx/**", "*.app", "*.git", ".git",
    "*.wav", "*.mp3", "*.ogg", "*.pcm",
    "*.mht", "*.suo", "*.sdf", "*.jnlp",
    "*.chm", "*.epub", "*.mobi", "*.ttf",
    "*.mp4", "*.avi", "*.flv", "*.mov", "*.mkv", "*.swf", "*.swc",
    "*.ppt", "*.pptx", "*.docx", "*.xlt", "*.xls", "*.xlsx", "*.odt", "*.wps",
    "*.msi", "*.crx", "*.deb", "*.vfd", "*.apk", "*.ipa", "*.bin", "*.msu",
    "*.gba", "*.sfc", "*.078", "*.nds", "*.smd", "*.smc",
    "*.linux2", "*.win32", "*.darwin", "*.freebsd", "*.linux", "*.android",
}
for _, pattern in ipairs(ignore) do
    opt.wildignore:append(pattern)
end

pcall(function() vim.cmd.language("en") end)
pcall(function() vim.cmd.language("en_US.UTF-8") end)
vim.cmd.nohlsearch()

opt.linespace = 2
