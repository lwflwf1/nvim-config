-- Picker over the live snacks terminals (Snacks.terminal.list()): filter,
-- <CR> shows and focuses one, <C-x> kills it; the preview shows the live
-- terminal buffer (the default `file` previewer follows `item.buf`).
-- Terminals are keyed by cmd+cwd+count (see snacks/terminal.lua), so every
-- `N<M-=>` instance and the `<M-+>` per-tab terminal shows up here. Bound to
-- <leader>fe and :Terminals. Kill reuses snacks' `bufdelete` action on the
-- item's buffer (<C-x>, same key the buffers/git/marks/scratch pickers use) --
-- no custom action needed.
local M = {}

--- Label for the picker: the OSC title (term_title) when the process set one,
--- else the command's basename parsed from the `term://cwd//<job>:<cmd>`
--- buffer name. nvim defaults term_title to the buffer name until an OSC
--- title arrives, so that is treated as unset. The instance id (count) is
--- prefixed when non-zero -- M.open doesn't store it, but it is the leading
--- `N: ` of the winbar it builds.
---@param t snacks.terminal
---@return string
local function title(t)
    local name = vim.b[t.buf].term_title
    if not name or name == "" or name:find("^term://") then
        local bufname = vim.api.nvim_buf_get_name(t.buf)
        local cmd = bufname:match("^term://.*//%d+:(.*)$") or bufname
        name = vim.fn.fnamemodify(cmd, ":t")
    end
    local winbar = (t.opts.wo and t.opts.wo.winbar) or ""
    local count = tonumber(winbar:match("^(%d+):")) or 0
    return count > 0 and (count .. ": " .. name) or name
end

--- Open the terminal picker.
function M.pick()
    Snacks.picker.pick({
        title = "Terminals",
        format = "text",
        finder = function()
            local items = {}
            for _, t in ipairs(Snacks.terminal.list()) do
                local label = title(t)
                items[#items + 1] = {
                    text = label,
                    -- preview (default `file` previewer) shows the buffer
                    -- itself; title labels the preview with the same text
                    title = label,
                    win = t,
                    buf = t.buf,
                    lastused = vim.fn.getbufinfo(t.buf)[1].lastused,
                }
            end
            table.sort(items, function(a, b) return a.lastused > b.lastused end)
            return items
        end,
        actions = {
            --- Show and focus the selected terminal.
            confirm = function(picker, item)
                local term = item and item.win
                picker:close()
                if term then
                    -- Deferred a tick on purpose: the picker's preview float
                    -- shows this buffer and is only torn down on the next
                    -- tick. `Show()` on a hidden terminal does `split
                    -- sbuffer`; with the preview still up, `:sbuffer` jumps to
                    -- that float, which the picker close then wipes.
                    vim.schedule(function()
                        if term:buf_valid() then
                            term:show():focus()
                        end
                    end)
                end
            end,
        },
        win = {
            input = {
                keys = {
                    ["<c-x>"] = { "bufdelete", mode = { "n", "i" }, desc = "Kill terminal" },
                },
            },
        },
    })
end

function M.setup()
    vim.keymap.set("n", "<leader>fe", M.pick, { noremap = true, silent = true, desc = "Terminals" })
    vim.api.nvim_create_user_command("Terminals", M.pick, { desc = "Pick a terminal" })
end

return M
