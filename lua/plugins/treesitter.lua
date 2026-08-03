return {
    {
        "nvim-treesitter/nvim-treesitter",
        build = ":TSUpdate",
        lazy = false,
        dependencies = {
            "nvim-treesitter/nvim-treesitter-textobjects",
            "nvim-treesitter/nvim-treesitter-context",
        },
        init = function()
            vim.env.CC = "gcc"
            vim.g.no_plugin_maps = true
        end,
        config = function()
            -- Override systemverilog parser to use personal fork (dynamic branch tracking)
            local parsers = require("nvim-treesitter.parsers")
            parsers.systemverilog = {
                install_info = {
                    url = "https://github.com/lwflwf1/tree-sitter-systemverilog",
                    branch = "master",
                    queries = "queries",
                },
                maintainers = { "@lwflwf1" },
                tier = 2,
            }
            -- TSUpdate reloads parsers module; re-apply override
            vim.api.nvim_create_autocmd("User", {
                pattern = "TSUpdate",
                callback = function()
                    local p = require("nvim-treesitter.parsers")
                    p.systemverilog = {
                        install_info = {
                            url = "https://github.com/lwflwf1/tree-sitter-systemverilog",
                            branch = "master",
                            queries = "queries",
                        },
                        maintainers = { "@lwflwf1" },
                        tier = 2,
                    }
                end,
            })

            require("nvim-treesitter").install(require("config.parsers"))

            vim.api.nvim_create_autocmd("FileType", {
                callback = function(args)
                    local ft = vim.bo[args.buf].filetype
                    if ft == "tc" or ft == "mako" or ft == "ralf" then return end
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
                    include_surrounding_whitespace = false,
                    selection_modes = {
                        ['@function.outer']    = 'V',
                        ['@class.outer']       = 'V',
                        ['@conditional.outer'] = 'V',
                        ['@loop.outer']        = 'V',
                        ['@block.outer']       = 'V',
                        ['@parameter.outer']   = 'v',
                        ['@parameter.inner']   = 'v',
                        ['@call.outer']        = 'v',
                        ['@call.inner']        = 'v',
                        ['@assignment.outer']  = 'v',
                        ['@constraint.outer']  = 'V',
                        ['@covergroup.outer']  = 'V',
                        ['@property.outer']    = 'V',
                    },
                },
                move = {
                    set_jumps = true,
                },
                swap = {
                    enable = true,
                },
            })

            local ts_sel = require("nvim-treesitter-textobjects.select")
            local ts_move = require("nvim-treesitter-textobjects.move")
            local ts_swap = require("nvim-treesitter-textobjects.swap")
            local ts_repeat = require("nvim-treesitter-textobjects.repeatable_move")

            -- Select textobjects
            vim.keymap.set({ "x", "o" }, "af", function() ts_sel.select_textobject("@function.outer") end, { desc = "outer function" })
            vim.keymap.set({ "x", "o" }, "if", function() ts_sel.select_textobject("@function.inner") end, { desc = "inner function" })
            vim.keymap.set({ "x", "o" }, "ac", function() ts_sel.select_textobject("@class.outer") end, { desc = "outer class" })
            vim.keymap.set({ "x", "o" }, "ic", function() ts_sel.select_textobject("@class.inner") end, { desc = "inner class" })
            vim.keymap.set({ "x", "o" }, "ad", function() ts_sel.select_textobject("@conditional.outer") end, { desc = "outer conditional" })
            vim.keymap.set({ "x", "o" }, "id", function() ts_sel.select_textobject("@conditional.inner") end, { desc = "inner conditional" })
            vim.keymap.set({ "x", "o" }, "al", function() ts_sel.select_textobject("@loop.outer") end, { desc = "outer loop" })
            vim.keymap.set({ "x", "o" }, "il", function() ts_sel.select_textobject("@loop.inner") end, { desc = "inner loop" })
            vim.keymap.set({ "x", "o" }, "ak", function() ts_sel.select_textobject("@block.outer") end, { desc = "outer block" })
            vim.keymap.set({ "x", "o" }, "ik", function() ts_sel.select_textobject("@block.inner") end, { desc = "inner block" })
            vim.keymap.set({ "x", "o" }, "aC", function() ts_sel.select_textobject("@call.outer") end, { desc = "outer call" })
            vim.keymap.set({ "x", "o" }, "iC", function() ts_sel.select_textobject("@call.inner") end, { desc = "inner call" })
            vim.keymap.set({ "x", "o" }, "aa", function() ts_sel.select_textobject("@parameter.outer") end, { desc = "outer parameter" })
            vim.keymap.set({ "x", "o" }, "ia", function() ts_sel.select_textobject("@parameter.inner") end, { desc = "inner parameter" })
            vim.keymap.set({ "x", "o" }, "aA", function() ts_sel.select_textobject("@assignment.outer") end, { desc = "outer assignment" })
            vim.keymap.set({ "x", "o" }, "iA", function() ts_sel.select_textobject("@assignment.inner") end, { desc = "inner assignment" })
            vim.keymap.set({ "x", "o" }, "ar", function() ts_sel.select_textobject("@constraint.outer") end, { desc = "outer constraint" })
            vim.keymap.set({ "x", "o" }, "ir", function() ts_sel.select_textobject("@constraint.inner") end, { desc = "inner constraint" })
            vim.keymap.set({ "x", "o" }, "ag", function() ts_sel.select_textobject("@covergroup.outer") end, { desc = "outer covergroup" })
            vim.keymap.set({ "x", "o" }, "ig", function() ts_sel.select_textobject("@covergroup.inner") end, { desc = "inner covergroup" })
            vim.keymap.set({ "x", "o" }, "ae", function() ts_sel.select_textobject("@property.outer") end, { desc = "outer property" })
            vim.keymap.set({ "x", "o" }, "ie", function() ts_sel.select_textobject("@property.inner") end, { desc = "inner property" })

            -- Move: start jumps
            vim.keymap.set("n", "]f", function() ts_move.goto_next_start("@function.outer") end, { desc = "next function" })
            vim.keymap.set("n", "[f", function() ts_move.goto_previous_start("@function.outer") end, { desc = "prev function" })
            vim.keymap.set("n", "]d", function() ts_move.goto_next_start("@conditional.outer") end, { desc = "next conditional" })
            vim.keymap.set("n", "[d", function() ts_move.goto_previous_start("@conditional.outer") end, { desc = "prev conditional" })
            vim.keymap.set("n", "]l", function() ts_move.goto_next_start("@loop.outer") end, { desc = "next loop" })
            vim.keymap.set("n", "[l", function() ts_move.goto_previous_start("@loop.outer") end, { desc = "prev loop" })
            vim.keymap.set("n", "]k", function() ts_move.goto_next_start("@block.outer") end, { desc = "next block" })
            vim.keymap.set("n", "[k", function() ts_move.goto_previous_start("@block.outer") end, { desc = "prev block" })
            vim.keymap.set("n", "]C", function() ts_move.goto_next_start("@call.outer") end, { desc = "next call" })
            vim.keymap.set("n", "[C", function() ts_move.goto_previous_start("@call.outer") end, { desc = "prev call" })
            vim.keymap.set("n", "]a", function() ts_move.goto_next_start("@parameter.outer") end, { desc = "next parameter" })
            vim.keymap.set("n", "[a", function() ts_move.goto_previous_start("@parameter.outer") end, { desc = "prev parameter" })
            vim.keymap.set("n", "]A", function() ts_move.goto_next_start("@assignment.outer") end, { desc = "next assignment" })
            vim.keymap.set("n", "[A", function() ts_move.goto_previous_start("@assignment.outer") end, { desc = "prev assignment" })
            vim.keymap.set("n", "]r", function() ts_move.goto_next_start("@constraint.outer") end, { desc = "next constraint" })
            vim.keymap.set("n", "[r", function() ts_move.goto_previous_start("@constraint.outer") end, { desc = "prev constraint" })
            vim.keymap.set("n", "]g", function() ts_move.goto_next_start("@covergroup.outer") end, { desc = "next covergroup" })
            vim.keymap.set("n", "[g", function() ts_move.goto_previous_start("@covergroup.outer") end, { desc = "prev covergroup" })
            vim.keymap.set("n", "]e", function() ts_move.goto_next_start("@property.outer") end, { desc = "next property" })
            vim.keymap.set("n", "[e", function() ts_move.goto_previous_start("@property.outer") end, { desc = "prev property" })

            -- Move: end jumps
            vim.keymap.set("n", "]F", function() ts_move.goto_next_end("@function.outer") end, { desc = "next function end" })
            vim.keymap.set("n", "[F", function() ts_move.goto_previous_end("@function.outer") end, { desc = "prev function end" })
            vim.keymap.set("n", "]D", function() ts_move.goto_next_end("@conditional.outer") end, { desc = "next conditional end" })
            vim.keymap.set("n", "[D", function() ts_move.goto_previous_end("@conditional.outer") end, { desc = "prev conditional end" })
            vim.keymap.set("n", "]R", function() ts_move.goto_next_end("@constraint.outer") end, { desc = "next constraint end" })
            vim.keymap.set("n", "[R", function() ts_move.goto_previous_end("@constraint.outer") end, { desc = "prev constraint end" })
            vim.keymap.set("n", "]G", function() ts_move.goto_next_end("@covergroup.outer") end, { desc = "next covergroup end" })
            vim.keymap.set("n", "[G", function() ts_move.goto_previous_end("@covergroup.outer") end, { desc = "prev covergroup end" })
            vim.keymap.set("n", "]E", function() ts_move.goto_next_end("@property.outer") end, { desc = "next property end" })
            vim.keymap.set("n", "[E", function() ts_move.goto_previous_end("@property.outer") end, { desc = "prev property end" })

            -- Move: next jumps
            vim.keymap.set("n", "]c", function() ts_move.goto_next("@class.outer") end, { desc = "next class" })
            vim.keymap.set("n", "[c", function() ts_move.goto_previous("@class.outer") end, { desc = "prev class" })

            -- Swap
            vim.keymap.set("n", "<leader>t>", function() ts_swap.swap_next("@parameter.inner") end, { desc = "swap param right" })
            vim.keymap.set("n", "<leader>t<", function() ts_swap.swap_previous("@parameter.inner") end, { desc = "swap param left" })

            -- Repeatable move with builtin f/t integration
            vim.keymap.set({ "n", "x", "o" }, ";", ts_repeat.repeat_last_move_next, { desc = "repeat last move" })
            vim.keymap.set({ "n", "x", "o" }, ",", ts_repeat.repeat_last_move_previous, { desc = "repeat last move reverse" })
            vim.keymap.set({ "n", "x", "o" }, "f", ts_repeat.builtin_f_expr, { expr = true, desc = "f with repeat" })
            vim.keymap.set({ "n", "x", "o" }, "F", ts_repeat.builtin_F_expr, { expr = true, desc = "F with repeat" })
            vim.keymap.set({ "n", "x", "o" }, "t", ts_repeat.builtin_t_expr, { expr = true, desc = "t with repeat" })
            vim.keymap.set({ "n", "x", "o" }, "T", ts_repeat.builtin_T_expr, { expr = true, desc = "T with repeat" })
        end,
    },
    {
        "nvim-treesitter/nvim-treesitter-context",
        event = "BufReadPre",
        opts = {
            max_lines = 5,
            multiline_threshold = 20,
            trim_scope = "outer",
            mode = "cursor",
            separator = nil,
            zindex = 50,
        },
        keys = {
            {
                "<leader>ut",
                function()
                    require("treesitter-context").toggle()
                end,
                desc = "Toggle treesitter context",
            },
            {
                "gs",
                function()
                    require("treesitter-context").go_to_context(vim.v.count1)
                end,
                desc = "Goto scope/context",
                silent = true,
            },
        },
    },
}
