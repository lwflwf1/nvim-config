return {
    {
        "nvim-treesitter/nvim-treesitter",
        build = ":TSUpdate",
        lazy = false,
        dependencies = {
            "nvim-treesitter/nvim-treesitter-textobjects",
        },
        init = function()
            vim.env.CC = "gcc"
        end,
        config = function()
            require("nvim-treesitter").install({
                "python", "perl", "systemverilog",
                "lua", "vim", "vimdoc", "bash",
                "markdown", "markdown_inline",
                "c", "cpp", "go", "rust",
                "json", "yaml", "toml",
                "regex", "gitcommit", "gitignore",
                "diff", "html", "css",
                "make", "cmake", "dockerfile",
                "git_rebase", "gitattributes",
            })

            vim.api.nvim_create_autocmd("FileType", {
                callback = function(args)
                    local ft = vim.bo[args.buf].filetype
                    if ft == "tc" or ft == "mako" then return end
                    local ok = pcall(vim.treesitter.start, args.buf)
                    if ok then
                        local ft = vim.bo[args.buf].filetype
                        local has_query, query = pcall(vim.treesitter.query.get, ft, "indents")
                        if has_query and query then
                            vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
                        end
                    end
                end,
            })

            require("nvim-treesitter-textobjects").setup({
                select = {
                    lookahead = true,
                    selection_modes = {
                        ['@function.outer'] = 'V',
                        ['@class.outer'] = 'V',
                    },
                },
                move = {
                    set_jumps = true,
                },
            })

            local ts_select = require("nvim-treesitter-textobjects.select")
            local ts_move = require("nvim-treesitter-textobjects.move")

            vim.keymap.set({ "x", "o" }, "af", function()
                ts_select.select_textobject("@function.outer")
            end, { desc = "Select outer function" })
            vim.keymap.set({ "x", "o" }, "if", function()
                ts_select.select_textobject("@function.inner")
            end, { desc = "Select inner function" })
            vim.keymap.set({ "x", "o" }, "ac", function()
                ts_select.select_textobject("@class.outer")
            end, { desc = "Select outer class" })
            vim.keymap.set({ "x", "o" }, "ic", function()
                ts_select.select_textobject("@class.inner")
            end, { desc = "Select inner class" })

            vim.keymap.set("n", "]f", function()
                ts_move.goto_next_start("@function.outer")
            end, { desc = "Next function start" })
            vim.keymap.set("n", "]c", function()
                ts_move.goto_next_start("@class.outer")
            end, { desc = "Next class start" })
            vim.keymap.set("n", "[f", function()
                ts_move.goto_previous_start("@function.outer")
            end, { desc = "Previous function start" })
            vim.keymap.set("n", "[c", function()
                ts_move.goto_previous_start("@class.outer")
            end, { desc = "Previous class start" })
        end,
    },
}
