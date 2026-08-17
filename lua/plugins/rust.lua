return {
    {
        "mrcjkb/rustaceanvim",
        version = "^9",
        lazy = false,
        init = function()
            vim.g.rustaceanvim = {
                tools = {
                    executor = "termopen",
                    test_executor = "termopen",
                    enable_clippy = true,
                    reload_workspace_from_cargo_toml = true,
                    code_actions = {
                        group_icon = " ▶",
                    },
                    float_win_config = {
                        auto_focus = false,
                    },
                },
                server = {
                    on_attach = function(client, bufnr)
                        local bopts = function(desc)
                            return { buffer = bufnr, silent = true, noremap = true, desc = desc }
                        end

                        require("config.lsp").on_attach(client, bufnr)

                        vim.keymap.set("n", "K", function()
                            local winid = require("ufo").peekFoldedLinesUnderCursor()
                            if not winid then
                                vim.cmd("RustLsp hover actions")
                            end
                        end, bopts("Peek fold or Rust hover actions"))

                        vim.keymap.set("n", "<leader>ra", "<cmd>RustLsp codeAction<CR>", bopts("Rust code action"))
                        vim.keymap.set("n", "<leader>rr", "<cmd>RustLsp run<CR>", bopts("Run"))
                        vim.keymap.set("n", "<leader>rt", "<cmd>RustLsp testables<CR>", bopts("Testables"))
                        vim.keymap.set("n", "<leader>rc", "<cmd>RustLsp openCargo<CR>", bopts("Open Cargo.toml"))
                        vim.keymap.set("n", "<leader>ro", "<cmd>RustLsp openDocs<CR>", bopts("Open docs"))
                        vim.keymap.set("n", "<leader>rp", "<cmd>RustLsp parentModule<CR>", bopts("Parent module"))
                        vim.keymap.set("n", "<leader>rm", "<cmd>RustLsp expandMacro<CR>", bopts("Expand macro"))
                        vim.keymap.set("n", "<leader>rl", "<cmd>RustLsp joinLines<CR>", bopts("Join lines"))
                        vim.keymap.set("n", "<leader>rM", "<cmd>RustLsp moveItem<CR>", bopts("Move item"))
                        vim.keymap.set("n", "<leader>rC", "<cmd>RustLsp flyCheck<CR>", bopts("Fly check (clippy)"))
                        vim.keymap.set("v", "<leader>ra", "<cmd>RustLsp codeAction<CR>", bopts("Rust code action"))
                        vim.keymap.set("v", "<leader>rl", "<cmd>RustLsp joinLines<CR>", bopts("Join lines"))
                        vim.keymap.set("v", "<leader>rM", function()
                            vim.cmd("RustLsp moveItem")
                        end, bopts("Move item"))
                    end,
                    default_settings = {
                        ["rust-analyzer"] = {
                            cargo = {
                                buildScripts = { enable = true },
                                features = "all",
                            },
                            procMacro = { enable = true },
                            check = {
                                command = "clippy",
                                allTargets = true,
                                workspace = true,
                            },
                            imports = {
                                granularity = { group = "module" },
                                prefix = "crate",
                            },
                            highlightRelated = {
                                references = { enable = true },
                                closureCaptures = { enable = true },
                            },
                            hover = {
                                actions = {
                                    enable = true,
                                    gotoTypeDef = { enable = true },
                                    implementations = { enable = true },
                                    references = { enable = true },
                                    run = { enable = true },
                                },
                                documentation = { enable = true },
                            },
                            completion = {
                                postfix = { enable = true },
                                autoimport = { enable = true },
                            },
                            diagnostics = { enable = true },
                            lens = {
                                enable = true,
                                implementations = { enable = true },
                                references = {
                                    adt = { enable = true },
                                    enumVariant = { enable = true },
                                    method = { enable = true },
                                    trait = { enable = true },
                                },
                                run = { enable = true },
                            },
                            inlayHints = {
                                chainingHints = { enable = true },
                                typeHints = { enable = true },
                                parameterHints = { enable = true },
                                closingBraceHints = { enable = true },
                                lifetimeElisionHints = { enable = "always" },
                                bindingModeHints = { enable = true },
                                expressionAdjustmentHints = { enable = "always" },
                            },
                        },
                    },
                },
            }
        end,
    },
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
            { "<leader>ru", function() require("crates").update_crate() end, desc = "Update crate", ft = "toml" },
            { "<leader>ra", function() require("crates").update_all_crates() end, desc = "Update all crates", ft = "toml" },
            { "<leader>rg", function() require("crates").upgrade_crate() end, desc = "Upgrade crate", ft = "toml" },
            { "<leader>rb", function() require("crates").upgrade_all_crates() end, desc = "Upgrade all crates", ft = "toml" },
            { "<leader>rv", function() require("crates").show_versions_popup() end, desc = "Show versions", ft = "toml" },
            { "<leader>rf", function() require("crates").show_features_popup() end, desc = "Show features", ft = "toml" },
            { "<leader>rd", function() require("crates").show_dependencies_popup() end, desc = "Show dependencies", ft = "toml" },
            { "<leader>rs", function() require("crates").open_repository() end, desc = "Open repo", ft = "toml" },
            { "<leader>rh", function() require("crates").open_documentation() end, desc = "Open docs", ft = "toml" },
            { "<leader>ri", function() require("crates").open_crates_io() end, desc = "Open crates.io", ft = "toml" },
            { "<leader>rt", function() require("crates").toggle() end, desc = "Toggle UI", ft = "toml" },
            { "<leader>re", function() require("crates").reload() end, desc = "Reload", ft = "toml" },
            { "<leader>rx", function() require("crates").expand_plain_crate_to_inline_table() end, desc = "Expand to inline table", ft = "toml" },
            { "<leader>rq", function() require("crates").extract_crate_into_table() end, desc = "Extract to table", ft = "toml" },
            { "<leader>rw", function() require("crates").open_homepage() end, desc = "Open homepage", ft = "toml" },
            { "<leader>rl", function() require("crates").open_lib_rs() end, desc = "Open lib.rs", ft = "toml" },
            { "<leader>ru", function() require("crates").update_crates() end, desc = "Update crates (visual)", mode = "v", ft = "toml" },
            { "<leader>rg", function() require("crates").upgrade_crates() end, desc = "Upgrade crates (visual)", mode = "v", ft = "toml" },
        },
    },
}
