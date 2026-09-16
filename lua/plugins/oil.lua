-- Show the current directory in the oil winbar (official recipe)
function _G.get_oil_winbar()
    local bufnr = vim.api.nvim_win_get_buf(vim.g.statusline_winid)
    local dir = require("oil").get_current_dir(bufnr)
    if dir then
        return vim.fn.fnamemodify(dir, ":~")
    else
        return vim.api.nvim_buf_get_name(0)
    end
end

-- Overlay a full-width, centered one-char label on each candidate window's
-- winbar and return the window id whose label the user pressed (nil on cancel).
-- The winbar (the window's top row) is used so the label never covers code;
-- replaced with vim.ui.select's window picker.
local function pick_window_with_labels(candidates)
    local labels = "asdfghjklqwertyuiopzxcvbnm"
    if #candidates == 0 then return nil end

    vim.api.nvim_set_hl(0, "OilWinLabel", { fg = "#111111", bg = "#ffcc00", bold = true, default = true })
    local by_key, saved = {}, {}
    for i, winid in ipairs(candidates) do
        local ch = labels:sub(i, i)
        if ch == "" then break end
        by_key[ch] = winid
        saved[#saved + 1] = { win = winid, winbar = vim.api.nvim_get_option_value("winbar", { win = winid }) }
        -- %#hl# then %=..%= centers the char; everything (incl. fill) is highlighted
        vim.api.nvim_set_option_value("winbar", "%#OilWinLabel#%=" .. ch .. "%=", { win = winid })
    end

    vim.cmd.redraw()
    local ok, ch = pcall(vim.fn.getcharstr)
    for _, s in ipairs(saved) do
        if vim.api.nvim_win_is_valid(s.win) then
            vim.api.nvim_set_option_value("winbar", s.winbar, { win = s.win })
        end
    end
    vim.cmd.redraw()

    if ok and type(ch) == "string" and ch ~= "" then return by_key[ch] end
    return nil
end

return {
    "stevearc/oil.nvim",
    -- Official recommendation: lazy loading oil is "very tricky to make it
    -- work correctly in all situations" (breaks `nvim .` dir takeover)
    lazy = false,
    dependencies = {
        "nvim-tree/nvim-web-devicons",
        "malewicz1337/oil-git.nvim",
    },
    keys = {
        {
            "<leader>ee",
            function()
                -- Close an existing oil sidebar in the CURRENT tab only
                -- (nvim_list_wins() spans all tabs and closed other tabs' sidebars)
                for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
                    if vim.api.nvim_win_get_config(winid).relative == "" then
                        local buf = vim.api.nvim_win_get_buf(winid)
                        if vim.bo[buf].filetype == "oil" then
                            if #vim.api.nvim_tabpage_list_wins(0) > 1 then
                                vim.api.nvim_win_close(winid, true)
                            end
                            return
                        end
                    end
                end
                -- oil.open() opens in the CURRENT window (its vertical/split
                -- opts only apply to preview), so the manual topleft vsplit is
                -- the correct way to get a sidebar.
                vim.cmd("topleft vsplit")
                require("oil").open()
                vim.api.nvim_win_resize(0, 40, -1)
                vim.wo.winfixwidth = true
            end,
            desc = "Oil (sidebar)",
        },
        {
            "<leader>ef",
            function() require("oil").toggle_float() end,
            desc = "Oil (float)",
        },
        { "-", "<CMD>Oil<CR>", desc = "Open parent directory" },
    },
    opts = {
        default_file_explorer = true,
        skip_confirm_for_simple_edits = true,
        keymaps = {
            ["<C-h>"] = "actions.select_split",
            ["<C-v>"] = "actions.select_vsplit",
            ["<CR>"] = {
                callback = function()
                    local oil = require("oil")
                    local entry = oil.get_cursor_entry()
                    if not entry then return end

                    if entry.type == "directory" then
                        oil.select()
                        return
                    end

                    -- Candidate windows: normal (non-floating) windows in the
                    -- CURRENT tab only. nvim_list_wins() spans all tabs, which
                    -- made files open in the first tab.
                    local candidates = {}
                    for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
                        if vim.api.nvim_win_get_config(winid).relative == "" then
                            local buf = vim.api.nvim_win_get_buf(winid)
                            if vim.bo[buf].buftype == "" and vim.bo[buf].filetype ~= "oil" then
                                table.insert(candidates, winid)
                            end
                        end
                    end

                    local function open_in(winid)
                        oil.select({
                            handle_buffer_callback = function(buf_id)
                                if vim.api.nvim_win_is_valid(winid) then
                                    vim.api.nvim_win_set_buf(winid, buf_id)
                                end
                            end,
                        })
                        -- Move focus to the target window (after oil.select returns,
                        -- since oil may re-focus during it).
                        if vim.api.nvim_win_is_valid(winid) then
                            vim.api.nvim_set_current_win(winid)
                        end
                    end

                    if #candidates == 0 then
                        oil.select({ vertical = true })
                    elseif #candidates == 1 then
                        open_in(candidates[1])
                    else
                        -- Multiple windows: overlay a one-char label on each and
                        -- open the file in the window whose label is pressed.
                        local winid = pick_window_with_labels(candidates)
                        if winid then open_in(winid) end
                    end
                end,
                desc = "Open file in chosen window / enter directory",
            },
            ["<leader>fx"] = {
                callback = function()
                    local oil = require("oil")
                    local prefills = { paths = oil.get_current_dir() }

                    local grug_far = require("grug-far")
                    if not grug_far.has_instance("explorer") then
                        grug_far.open({
                            instanceName = "explorer",
                            prefills = prefills,
                            staticTitle = "Find and Replace from Explorer",
                        })
                    else
                        grug_far.get_instance("explorer"):open()
                        grug_far.get_instance("explorer"):update_input_values(prefills, false)
                    end
                end,
                desc = "Find and Replace in directory",
            },
        },
        win_options = {
            wrap = false,
            signcolumn = "no",
            cursorcolumn = false,
            foldcolumn = "0",
            spell = false,
            list = false,
            conceallevel = 3,
            concealcursor = "nvic",
            winbar = "%!v:lua.get_oil_winbar()",
        },
        view_options = {
            show_hidden = true,
            natural_order = "fast",
            sort = {
                { "type", "asc" },
                { "name", "asc" },
            },
        },
        preview_win = {
            update_on_cursor_moved = true,
            preview_method = "fast_scratch",
            disable_preview = function(filename)
                return false
            end,
        },
        float = {
            padding = 2,
            max_width = 0,
            max_height = 0,
            border = nil,
            win_options = {
                winblend = 0,
            },
            preview_split = "auto",
        },
    },
}
