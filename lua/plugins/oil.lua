local project = require("config.project")

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
                vim.api.nvim_win_set_width(0, 40)
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
                    end

                    if #candidates == 0 then
                        oil.select({ vertical = true })
                    elseif #candidates == 1 then
                        open_in(candidates[1])
                    else
                        -- Multiple windows: let the user pick (vim.ui.select is
                        -- backed by snacks.picker.select in this config)
                        vim.ui.select(candidates, {
                            prompt = "Open file in window:",
                            format_item = function(winid)
                                local buf = vim.api.nvim_win_get_buf(winid)
                                local name = vim.api.nvim_buf_get_name(buf)
                                if name == "" then name = "[No Name]" end
                                return ("win %d  %s"):format(winid, vim.fn.fnamemodify(name, ":t"))
                            end,
                        }, function(winid)
                            if winid then open_in(winid) end
                        end)
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
    init = function()
        vim.api.nvim_create_autocmd("VimEnter", {
            callback = function()
                local root = project.project_root(0)
                if root then vim.fn.chdir(root) end
            end,
        })
    end,
}
