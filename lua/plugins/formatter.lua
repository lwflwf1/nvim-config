return {
    {
        "stevearc/conform.nvim",
        opts = {
            formatters_by_ft = {
                lua = { "stylua" },
                python = { "ruff_format" },
                perl = { "perltidy" },
                rust = { "rustfmt" },
                javascript = { "prettierd", "prettier" },
                typescript = { "prettierd", "prettier" },
                json = { "prettierd", "prettier" },
                yaml = { "prettierd", "prettier" },
                markdown = { "prettierd", "prettier" },
                systemverilog = { "verible-verilog-format" },
                verilog = { "verible-verilog-format" },
            },
            formatters = {
                ["verible-verilog-format"] = {
                    prepend_args = {
                        "--indentation_spaces", "4",
                        "--column_limit", "120",
                        "--wrap_end_else_clauses",
                    },
                },
            },
            format_on_save = false,
            default_format_opts = {
                lsp_format = "fallback",
            },
        },
        keys = {
            { "<leader>lf", function() require("conform").format({ async = true, lsp_format = "fallback" }) end, mode = { "n", "x" }, desc = "Format file" },
        },
        config = function(_, opts)
            require("conform").setup(opts)
        end,
    },
}
