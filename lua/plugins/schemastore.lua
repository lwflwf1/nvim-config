return {
    {
        "b0o/schemastore.nvim",
        lazy = true,
        -- schemastore catalog is pulled on first load (then cached);
        -- LSP servers that use it load it lazily via config/lsp.lua
    },
}