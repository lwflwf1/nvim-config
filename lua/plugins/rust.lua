return {
    {
        "saecki/crates.nvim",
        tag = "stable",
        event = { "BufRead Cargo.toml" },
        opts = {
            lsp = {
                enabled = true,
                actions = true,
                completion = true,
                hover = true,
                on_attach = function(_, bufnr)
                    vim.keymap.set("n", "K", vim.lsp.buf.hover,
                        { buffer = bufnr, silent = true, desc = "Crates popup" })
                end,
            },
        },
        keys = {
            { "<leader>cu", function() require("crates").update_crate() end, desc = "Update crate" },
            { "<leader>ca", function() require("crates").update_all_crates() end, desc = "Update all crates" },
            { "<leader>cU", function() require("crates").upgrade_crate() end, desc = "Upgrade crate" },
            { "<leader>cv", function() require("crates").show_versions_popup() end, desc = "Show versions" },
            { "<leader>cf", function() require("crates").show_features_popup() end, desc = "Show features" },
            { "<leader>cd", function() require("crates").show_dependencies_popup() end, desc = "Show dependencies" },
            { "<leader>cR", function() require("crates").open_repository() end, desc = "Open repo" },
            { "<leader>cD", function() require("crates").open_documentation() end, desc = "Open docs" },
            { "<leader>cC", function() require("crates").open_crates_io() end, desc = "Open crates.io" },
            { "<leader>ct", function() require("crates").toggle() end, desc = "Toggle UI" },
            { "<leader>cE", function() require("crates").reload() end, desc = "Reload" },
            { "<leader>cA", function() require("crates").upgrade_all_crates() end, desc = "Upgrade all crates" },
            { "<leader>cx", function() require("crates").expand_plain_crate_to_inline_table() end, desc = "Expand to inline table" },
            { "<leader>cX", function() require("crates").extract_crate_into_table() end, desc = "Extract to table" },
            { "<leader>cH", function() require("crates").open_homepage() end, desc = "Open homepage" },
            { "<leader>cL", function() require("crates").open_lib_rs() end, desc = "Open lib.rs" },
            { "<leader>cu", function() require("crates").update_crates() end, desc = "Update crates (visual)", mode = "v" },
            { "<leader>cU", function() require("crates").upgrade_crates() end, desc = "Upgrade crates (visual)", mode = "v" },
        },
    },
}
