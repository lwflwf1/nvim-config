return {
    {
        "milanglacier/minuet-ai.nvim",
        version = false,
        config = function()
            require("minuet").setup({
                provider = "openai_fim_compatible",
                virtualtext = {
                    auto_trigger_ft = { "*" },
                    keymap = {
                        accept = "<C-l>",
                        accept_line = "<A-a>",
                        accept_n_lines = "<A-z>",
                        dismiss = "<A-e>",
                    },
                },
                provider_options = {
                    openai_fim_compatible = {
                        api_key = "DEEPSEEK_API_KEY",
                        name = "DeepSeek",
                        end_point = "https://api.deepseek.com/beta/completions",
                        model = "deepseek-v4-flash",
                        optional = {
                            max_tokens = 256,
                            top_p = 0.9,
                        },
                    },
                },
            })
        end,
    },
}
