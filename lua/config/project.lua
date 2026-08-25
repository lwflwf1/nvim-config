-- Project root detection + display, consolidated from the former
-- config/root_markers.lua, config/project_root.lua and core/rooter.lua.
--
-- - markers: the single source of truth for root markers.
-- - project_root(source): nearest-ancestor root (distance wins, markers have
--   no priority). Used for the cwd follower and by fzf/harpoon/etc.
-- - project_name(source): display name for lualine. .SOS has HIGHEST priority
--   (regardless of distance); otherwise the nearest of any other marker.
-- - BufEnter: set the window-local cwd to project_root (fzf/live-grep/:!-commands
--   /git all operate inside the project root automatically).
local M = {}

M.markers = {
    ".git", ".SOS", ".root", ".svn", ".hg",
    "Makefile", "Cargo.toml", "package.json",
}

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
function M.project_root(source)
    local path
    if type(source) == "number" then
        path = vim.api.nvim_buf_get_name(source)
    else
        path = source
    end
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

--- Display name for lualine: only the directory name, no path.
--- .SOS wins over any other marker (higher priority); if no .SOS is found
--- walking up, fall back to the nearest of any other marker (equal priority).
--- If no root marker (including .SOS) is found, returns nil so lualine hides
--- this component instead of showing a fallback directory name.
---@param source string|integer absolute path or buffer number (0 = current)
---@return string|nil directory name of the detected project root, or nil if none
function M.project_name(source)
    local path = (type(source) == "number") and vim.api.nvim_buf_get_name(source) or source
    local dir
    if path == "" then
        dir = vim.uv.cwd()
    else
        dir = vim.fs.dirname(vim.fs.abspath(path))
    end
    if not dir then dir = vim.uv.cwd() end

    -- 1) .SOS has highest priority, regardless of distance from the file.
    local sos = vim.fs.find(".SOS", { path = dir, upward = true })
    if sos and #sos > 0 then
        return vim.fs.basename(vim.fs.dirname(sos[1]))
    end

    -- 2) otherwise the nearest directory containing any other marker.
    local root = M.project_root(source)
    if root then
        return vim.fs.basename(root)
    end
    return nil
end

vim.api.nvim_create_autocmd("BufEnter", {
    callback = function()
        local buf = vim.api.nvim_get_current_buf()
        if vim.bo[buf].buftype ~= "" then return end
        if vim.api.nvim_buf_get_name(buf) == "" then return end
        local root = M.project_root(buf)
        if root and root ~= vim.fn.getcwd() then
            vim.cmd.lcd(root)
        end
    end,
})

return M
