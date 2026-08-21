-- Nearest-ancestor project root: walk UP one directory level at a time from the
-- file's own directory; the FIRST level that contains ANY root marker is the
-- root. (vim.fs.root instead iterates the marker list first, so an ambient
-- marker higher up the tree — e.g. .SOS above a user's .root — can win over a
-- nearer one. Here distance wins and markers have no priority.)
local markers = require("config.root_markers")

local function has_marker(dir)
    for _, mark in ipairs(markers) do
        if vim.uv.fs_stat(vim.fs.joinpath(dir, mark)) then
            return true
        end
    end
    return false
end

---@param source string|integer absolute path or buffer number (0 = current)
---@return string|nil absolute path of the nearest marker directory
local function project_root(source)
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

return project_root
