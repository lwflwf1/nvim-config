-- 默认主题的单一事实来源（方案 A）+ 记住上次选择（方案 B 的持久化）。
-- 启动：状态文件 > default；退出：VimLeavePre 把最终 colors_name 写回状态
-- 文件（picker 预览会临时换主题、取消时恢复，取退出时真值即可，
-- 不需要 hook picker 内部动作）。
local M = {}

M.default = "onedark"
M.statefile = vim.fn.stdpath("state") .. "/colorscheme"

function M.set(name)
    pcall(vim.cmd.colorscheme, name)
    -- 状态里的主题已失效（如插件被删）时回退默认
    if vim.g.colors_name == nil and name ~= M.default then
        pcall(vim.cmd.colorscheme, M.default)
    end
end

function M.setup()
    local f = io.open(M.statefile, "r")
    local saved
    if f then
        saved = f:read("*l")
        f:close()
    end
    if saved == nil or saved == "" then
        saved = M.default
    end
    M.set(saved)

    vim.api.nvim_create_autocmd("VimLeavePre", {
        group = vim.api.nvim_create_augroup("theme_state", { clear = true }),
        callback = function()
            local name = vim.g.colors_name
            if not name or name == "" then
                return
            end
            vim.fn.mkdir(vim.fn.fnamemodify(M.statefile, ":h"), "p")
            local out = io.open(M.statefile, "w")
            if out then
                out:write(name)
                out:close()
            end
        end,
    })
end

return M
