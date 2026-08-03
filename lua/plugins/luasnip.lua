return {
    {
        "L3MON4D3/LuaSnip",
        version = "2.*",
        event = "InsertEnter",
        build = "make install_jsregexp",
        dependencies = { "rafamadriz/friendly-snippets" },
        config = function()
            require("luasnip.loaders.from_vscode").lazy_load()
            require("luasnip.loaders.from_lua").lazy_load({
                paths = { vim.fn.stdpath("config") .. "/lua/snippets" },
            })
        end,
    },
}