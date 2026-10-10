-- Internal project module: root detection, auto-cwd and the manual root
-- picker. Consolidated from the former config/project.lua (itself the merge of
-- config/root_markers.lua, config/project_root.lua and core/rooter.lua), the
-- auto-cwd block in core/autocmds.lua and the toggle/pick helpers in
-- core/keymaps.lua.
--
-- - markers: the single source of truth for root markers (also used by
--   config/lsp.lua).
-- - get_root(source): the effective root -- the manual pin (<leader>pp) when
--   set, else the nearest-ancestor marker root (find_root; distance wins, no
--   marker priority). This is the fff index root / project gate.
-- - setup(): installs the auto-cwd BufEnter (global chdir) and the
--   <leader>p* keymaps (toggle / pin / picked-root pickers / switch file).
-- Public state (read outside): auto_enabled() drives the auto-cwd BufEnter and
-- the ui.lua cwd indicator color.
local M = {}

---@type string[]
M.markers = {
    ".git", ".SOS", ".root", ".svn", ".hg",
    "Makefile", "Cargo.toml", "package.json",
}

-- Manual root pin (<leader>pp / lualine left-click): set by M.pick's confirm
-- callback, cleared when auto-cwd is toggled back on.
local pinned_root = nil

-- Auto-cwd on/off (default on). Toggled by <leader>pa / the lualine click.
local auto_enabled = true

---@return boolean
function M.auto_enabled()
    return auto_enabled
end

local function base_path()
    -- Base directory holding the project checkouts (RHEL6 work trees). Login
    -- name from the passwd DB: robust when $USER is unset (csh `set` vs
    -- `setenv`, sudo, tmux) and works on Windows too ($USERNAME instead).
    return "/proj/crane/wa/" .. vim.uv.os_get_passwd().username
end

local function has_marker(dir)
    for _, mark in ipairs(M.markers) do
        if vim.uv.fs_stat(vim.fs.joinpath(dir, mark)) then
            return true
        end
    end
    return false
end

---@param source string|integer absolute path or buffer number (0 = current)
---@return string|nil absolute path of the nearest marker directory
local function find_root(source)
    local path
    if type(source) == "number" then
        path = vim.api.nvim_buf_get_name(source)
    else
        path = source
    end
    ---@cast path string
    if path == "" then return nil end
    local dir = vim.fs.dirname(vim.fs.abspath(path))
    while dir do
        if has_marker(dir) then
            return dir
        end
        local parent = vim.fs.dirname(dir)
        if parent == dir then break end
        dir = parent
    end
    return nil
end

--- Effective root: the manual pin when set, otherwise the detected root of
--- `source` (find_root).
---@param source string|integer absolute path or buffer number (0 = current)
---@return string|nil
function M.get_root(source)
    return pinned_root or find_root(source)
end

-- Auto project cwd: <leader>pa toggles it (default on; see the BufEnter in
-- setup). Shared with the lualine cwd click (ui.lua).
function M.toggle_auto()
    auto_enabled = not auto_enabled
    if auto_enabled then
        pinned_root = nil
    end
    vim.notify("Auto cwd: " .. (auto_enabled and "ON" or "OFF"), vim.log.levels.INFO)
end

-- fd args for the root picker: bound the walk (NFS!), follow symlinks (the
-- RHEL6 project trees live behind them). fd skips hidden and gitignored
-- entries by itself.
local FD_DIRS_ARGS = {
    "--type", "d",
    "--max-depth", "3",
    "--follow",
    "--exclude", "node_modules",
    "--exclude", "build",
    "--exclude", "dist",
}

-- Exclusions for the picked-root files finder (<leader>pf).
local exclude_patterns = {
    ".git", "node_modules", "build", "dist",
    "*.o", "*.obj", "*.so", "*.dll", "*.exe",
    "*.pyc", "*.png", "*.jpg", "*.pdf",
}

-- Pick a directory: input a root (prefilled with the current pin or the
-- project base dir), then fuzzy-pick one of the directories under it (or the
-- directory itself) from an fd stream. Calls cb(dir) on confirm.
---@param cb fun(dir: string)
local function pick_root(cb)
    local default = pinned_root or (base_path() .. "/")
    if vim.fn.isdirectory(default) == 0 then
        default = vim.fn.getcwd()
    end
    local v = vim.fn.input("Project root: ", default, "dir")
    if v == "" then return end
    local dir = vim.fn.fnamemodify(vim.fn.expand(v), ":p"):gsub("[/\\]+$", "")
    if vim.fn.isdirectory(dir) == 0 then
        vim.notify("Not a directory: " .. v, vim.log.levels.WARN)
        return
    end

    Snacks.picker.pick({
        prompt = "Project root> ",
        format = "text",
        preview = "directory",
        finder = function(_, ctx)
            local proc = require("snacks.picker.source.proc").proc({
                cmd = "fd",
                args = FD_DIRS_ARGS,
                cwd = dir,
                transform = function(item)
                    item.file = (vim.fs.normalize(vim.fs.joinpath(dir, item.text)):gsub("[/\\]+$", ""))
                end,
            }, ctx)
            -- the input dir itself first (lets you pick it as-is)
            return function(emit)
                emit({ text = vim.fs.basename(dir) .. "/", file = dir })
                proc(emit)
            end
        end,
        actions = {
            confirm = function(picker, item)
                picker:close()
                cb(item.file)
            end,
        },
    })
end

-- Pin a manual root: pick one, chdir there and turn auto-cwd off. Shared with
-- the lualine cwd left-click (plugins/ui.lua).
function M.pick()
    pick_root(function(dir)
        vim.fn.chdir(dir)
        pinned_root = dir
        auto_enabled = false
        vim.notify("Project cwd: " .. dir .. " (auto off)", vim.log.levels.INFO)
    end)
end

-- <leader>po: pick a root, then open the current file at the same relative
-- path under it. The relative path is taken against the current project root
-- (manual pin or detected marker), so the two trees must mirror each other.
local function switch_file()
    local abs_path = vim.api.nvim_buf_get_name(0)
    if abs_path == "" then
        vim.notify("No file in buffer", vim.log.levels.WARN)
        return
    end
    local cur_root = M.get_root(0)
    local rel = cur_root and vim.fs.relpath(cur_root, abs_path)
    if not rel then
        vim.notify("File not under a project root", vim.log.levels.WARN)
        return
    end
    pick_root(function(root)
        vim.cmd("edit " .. vim.fn.fnameescape(vim.fs.joinpath(root, rel)))
    end)
end

function M.setup()
    -- Single auto-cwd implementation (global chdir). Disabled by <leader>pa
    -- (M.toggle_auto) and by a manual root set via <leader>pp (M.pick).
    local auto_cwd_aug = vim.api.nvim_create_augroup("auto_cwd", { clear = true })
    local cwd_cache = {}
    vim.api.nvim_create_autocmd("BufEnter", {
        group = auto_cwd_aug,
        callback = function()
            if not auto_enabled then
                return
            end
            local path = vim.api.nvim_buf_get_name(0)
            if path == "" or vim.bo.buftype ~= "" then
                return
            end
            local dir = vim.fs.dirname(path)
            if cwd_cache[dir] == nil then
                cwd_cache[dir] = find_root(0) or dir
            end
            local target = cwd_cache[dir]
            if vim.fn.getcwd() ~= target then
                vim.fn.chdir(target)
            end
        end,
    })

    local map = function(lhs, rhs, desc)
        vim.keymap.set("n", lhs, rhs, { noremap = true, silent = true, desc = desc })
    end
    map("<leader>pa", M.toggle_auto, "Toggle auto project cwd")
    map("<leader>pp", M.pick, "Set project cwd (disables auto)")
    map("<leader>pf", function()
        pick_root(function(root)
            -- Project dirs' contents live behind symlinks; follow=true is
            -- required for the files finder to see them.
            Snacks.picker.files({ cwd = root, ignored = true, follow = true, exclude = exclude_patterns })
        end)
    end, "Find files in picked root")
    map("<leader>pg", function()
        pick_root(function(root) Snacks.picker.grep({ cwd = root }) end)
    end, "Live grep in picked root")
    map("<leader>pw", function()
        pick_root(function(root) Snacks.picker.grep_word({ cwd = root }) end)
    end, "Word search in picked root")
    map("<leader>po", switch_file, "Open same file in another project")
end

return M
