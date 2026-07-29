local root_markers = require("config.root_markers")

return {
    "stevearc/oil.nvim",
    dependencies = {
        "echasnovski/mini.nvim",
        "malewicz1337/oil-git.nvim",
    },
    event = "VeryLazy",
    keys = {
        {
            "<leader>ee",
            function()
                for _, win in ipairs(vim.api.nvim_list_wins()) do
                    local buf = vim.api.nvim_win_get_buf(win)
                    if vim.bo[buf].filetype == "oil" then
                        if #vim.api.nvim_list_wins() > 1 then
                            vim.api.nvim_win_close(win, true)
                        end
                        return
                    end
                end
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
                    else
                        local prev_winid = nil
                        local wins = vim.api.nvim_list_wins()
                        local cur_winid = vim.api.nvim_get_current_win()
                        for _, winid in ipairs(wins) do
                            if winid ~= cur_winid then
                                local buf = vim.api.nvim_win_get_buf(winid)
                                if vim.bo[buf].buftype == "" then
                                    prev_winid = winid
                                    break
                                end
                            end
                        end

                        if prev_winid and vim.api.nvim_win_is_valid(prev_winid) then
                            local target_winid = prev_winid
                            oil.select({
                                handle_buffer_callback = function(buf_id)
                                    if vim.api.nvim_win_is_valid(target_winid) then
                                        vim.api.nvim_win_set_buf(target_winid, buf_id)
                                    end
                                end,
                            })
                        else
                            oil.select({ vertical = true })
                        end
                    end
                end,
                desc = "Open file in right window / enter directory",
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
                local root = vim.fs.root(0, root_markers)
                if root then vim.fn.chdir(root) end
            end,
        })
    end,
}
