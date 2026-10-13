-- Copy the current buffer's full path to the clipboard. Shared by the <C-g>
-- keymap and the lualine filename right-click, so both stay in sync.
local M = {}

function M.copy()
    local path = vim.fn.expand("%:p")
    if path == "" then
        return
    end
    local ok = pcall(vim.fn.setreg, "+", path)
    local msg = ok and ("Copied: " .. path) or "Clipboard unavailable"
    if _G.Snacks then
        if ok then
            Snacks.notify.info(msg)
        else
            Snacks.notify.warn(msg)
        end
    else
        vim.notify(msg, ok and vim.log.levels.INFO or vim.log.levels.WARN)
    end
end

function M.setup()
    -- <C-g> normally shows the file name + position (:file); keep that and
    -- copy the path too. The fed <C-g> uses feedkeys "n" (noremap) so it runs
    -- the built-in, not this mapping. Notify goes to a float (Snacks) so it
    -- does not clobber <C-g>'s message.
    vim.keymap.set("n", "<C-g>", function()
        M.copy()
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-g>", true, false, true), "n", false)
    end, { desc = "File info + copy path" })
end

return M
