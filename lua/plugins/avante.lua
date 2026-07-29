return {
    {
        "yetone/avante.nvim",
        event = "VeryLazy",
        version = false,
        build = vim.fn.has("win32") ~= 0
            and "powershell -ExecutionPolicy Bypass -File Build.ps1 -BuildFromSource false"
            or "make",
        dependencies = {
            "nvim-treesitter/nvim-treesitter",
            "nvim-lua/plenary.nvim",
            "MunifTanjim/nui.nvim",
            "echasnovski/mini.nvim",
            "HakonHarnes/img-clip.nvim",
        },
        keys = {
            { "<leader>aa", "<cmd>AvanteAsk<CR>", desc = "Avante ask", mode = { "n", "v" } },
            { "<leader>ae", "<cmd>AvanteEdit<CR>", desc = "Avante edit", mode = { "n", "v" } },
            { "<leader>at", "<cmd>AvanteToggle<CR>", desc = "Avante toggle" },
        },
        opts = {
            provider = "deepseek",
            auto_suggestions_provider = "deepseek",
            providers = {
                deepseek = {
                    __inherited_from = "openai",
                    api_key_name = "DEEPSEEK_API_KEY",
                    endpoint = "https://api.deepseek.com",
                    model = "deepseek-v4-flash",
                    timeout = 30000,
                    extra_request_body = {
                        temperature = 0.1,
                        max_tokens = 8192,
                    },
                },
            },
            behaviour = {
                auto_suggestions = false,
                auto_set_highlight_group = true,
                auto_set_keymaps = true,
                auto_apply_diff_after_generation = false,
                support_paste_from_clipboard = false,
                minimize_diff = true,
            },
            hints = { enabled = true },
            windows = {
                ---@type "right" | "left" | "top" | "bottom"
                position = "right",
                wrap = true,
                width = 50,
                sidebar_header = {
                    enabled = true,
                    align = "center",
                    rounded = true,
                },
                input = {
                    prefix = "> ",
                },
            },
            highlights = {
                ---@type "dark" | "light"
                diff = "dark",
            },
            selector = {
                provider = "snacks",
            },
            input = {
                provider = "snacks",
            },
        },
    },
}
