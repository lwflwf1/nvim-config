return {
    {
        "milanglacier/minuet-ai.nvim",
        version = false,
        event = "InsertEnter",
        config = function()
            require("minuet").setup({
                provider = "openai_fim_compatible",
                provider_options = {
                    openai_fim_compatible = {
                        api_key = "LLM_API_KEY",
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
