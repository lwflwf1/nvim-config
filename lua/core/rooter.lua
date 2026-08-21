-- Follow the project root on buffer enter: from the current file's directory,
-- walk up until a root_markers entry is found (.root/.git/.SOS/Makefile/...) and
-- set the window-local cwd to it, so fzf/live-grep/:!-commands/git all operate
-- inside the project root automatically.
local project_root = require("config.project_root")

vim.api.nvim_create_autocmd("BufEnter", {
    callback = function()
        local buf = vim.api.nvim_get_current_buf()
        if vim.bo[buf].buftype ~= "" then return end
        if vim.api.nvim_buf_get_name(buf) == "" then return end
        local root = project_root(buf)
        if root and root ~= vim.fn.getcwd() then
            vim.cmd.lcd(root)
        end
    end,
})
