local M = {}
local root_markers = require("config.root_markers")

--- Set vim.g.goto_fallback = false to disable fallback to uctags/grep
--- when LSP returns no results for gd/gr/gi/gy. Default (nil) = enabled.

function M.setup()
    local capabilities = require("cmp_nvim_lsp").default_capabilities()

    local fallback_messages = {
        ["textDocument/definition"] = "No definition found",
        ["textDocument/references"] = "No references found",
        ["textDocument/implementation"] = "No implementation found",
        ["textDocument/typeDefinition"] = "No type definition found",
    }

    local function exec_fallback(method, fallback, word)
        if vim.g.goto_fallback == false then return end

        local ok, _ = pcall(vim.cmd, fallback .. " " .. word)
        if not ok then
            local msg = fallback_messages[method] or "No results found"
            vim.notify(msg .. ": " .. word, vim.log.levels.INFO)
        end
    end

    local method_to_cap = {
        ["textDocument/definition"] = "definitionProvider",
        ["textDocument/references"] = "referencesProvider",
        ["textDocument/implementation"] = "implementationProvider",
        ["textDocument/typeDefinition"] = "typeDefinitionProvider",
    }

    local function lsp_or_tags(method, fallback)
        return function()
            local word = vim.fn.expand("<cword>")
            if word == "" then return end

            local clients = vim.lsp.get_clients({ bufnr = 0 })
            if #clients == 0 then
                exec_fallback(method, fallback, word)
                return
            end

            local cap = method_to_cap[method]
            if cap then
                local supported = false
                for _, client in ipairs(clients) do
                    if (client.server_capabilities or {})[cap] then
                        supported = true
                        break
                    end
                end
                if not supported then
                    exec_fallback(method, fallback, word)
                    return
                end
            end

            vim.lsp.buf_request_all(0, method, function(client)
                local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
                if method == "textDocument/references" then
                    params.context = { includeDeclaration = true }
                end
                return params
            end, function(results)
                local all_items = {}
                for client_id, res in pairs(results) do
                    local client = assert(vim.lsp.get_client_by_id(client_id))
                    local locations = (res and res.result) and res.result or {}
                    local items = vim.lsp.util.locations_to_items(locations, client.offset_encoding)
                    vim.list_extend(all_items, items)
                end
                if next(all_items) then
                    vim.fn.setqflist(all_items)
                    vim.api.nvim_command("copen")
                    vim.api.nvim_command("cfirst")
                else
                    exec_fallback(method, fallback, word)
                end
            end)
        end
    end

    vim.keymap.set("n", "gd", lsp_or_tags("textDocument/definition", "tjump"),
        { silent = true, noremap = true, desc = "Go to definition (LSP, fallback uctags)" })
    vim.keymap.set("n", "grr", lsp_or_tags("textDocument/references", "tjump"),
        { silent = true, noremap = true, desc = "Go to references (LSP, fallback tjump)" })
    vim.keymap.set("n", "gri", lsp_or_tags("textDocument/implementation", "tjump"),
        { silent = true, noremap = true, desc = "Go to implementation (LSP, fallback uctags)" })
    vim.keymap.set("n", "grt", lsp_or_tags("textDocument/typeDefinition", "tjump"),
        { silent = true, noremap = true, desc = "Go to type definition (LSP, fallback uctags)" })

    local on_attach = function(client, bufnr)
        local bopts = function(desc)
            return { buffer = bufnr, silent = true, noremap = true, desc = desc }
        end

        vim.keymap.set("n", "K", vim.lsp.buf.hover, bopts("Hover"))
        vim.keymap.set("n", "gk", vim.lsp.buf.signature_help, bopts("Signature help"))
        vim.keymap.set("n", "<leader>dr", vim.lsp.buf.rename, bopts("LSP rename"))
        vim.keymap.set("n", "<leader>dn", function()
            vim.diagnostic.jump({ count = 1 })
        end, bopts("Next diagnostic"))
        vim.keymap.set("n", "<leader>dp", function()
            vim.diagnostic.jump({ count = -1 })
        end, bopts("Prev diagnostic"))
        vim.keymap.set("n", "<leader>dd", vim.diagnostic.open_float, bopts("Diagnostic float"))
        vim.keymap.set("n", "<leader>dl", function()
            vim.diagnostic.setloclist()
            vim.cmd("lopen")
        end, bopts("Diagnostics to loclist"))
        vim.keymap.set("n", "<leader>de", function()
            vim.diagnostic.setloclist({ severity = vim.diagnostic.severity.ERROR })
            vim.cmd("lopen")
        end, bopts("Errors only"))
        vim.keymap.set("n", "<leader>dw", function()
            vim.diagnostic.setloclist({ severity = vim.diagnostic.severity.WARN })
            vim.cmd("lopen")
        end, bopts("Warnings only"))
        vim.keymap.set("n", "<leader>di", function()
            vim.diagnostic.setloclist({ severity = vim.diagnostic.severity.INFO })
            vim.cmd("lopen")
        end, bopts("Info only"))
        vim.keymap.set("n", "<leader>dh", function()
            vim.diagnostic.setloclist({ severity = vim.diagnostic.severity.HINT })
            vim.cmd("lopen")
        end, bopts("Hints only"))
        vim.keymap.set("n", "<leader>dt", function()
            local disabled = vim.b[bufnr].diag_disabled or false
            vim.diagnostic.enable(disabled, { bufnr = 0 })
            vim.b[bufnr].diag_disabled = not disabled
            vim.notify(disabled and "diagnostics enabled" or "diagnostics disabled")
        end, bopts("Toggle diagnostics"))
        vim.keymap.set("n", "<leader>da", vim.lsp.buf.code_action, bopts("Code action"))
        vim.keymap.set("x", "<leader>da", vim.lsp.buf.code_action, bopts("Code action"))
    end

    vim.lsp.config.pyright = {
        cmd = { "pyright-langserver", "--stdio" },
        filetypes = { "python" },
        root_markers = { "pyproject.toml", "setup.py", "setup.cfg", "requirements.txt", ".git" },
        capabilities = capabilities,
        on_attach = on_attach,
    }

    vim.lsp.config.ruff = {
        cmd = { "ruff", "server" },
        filetypes = { "python" },
        root_markers = { "pyproject.toml", "setup.py", "setup.cfg", "requirements.txt", ".git" },
        capabilities = capabilities,
        on_attach = on_attach,
        settings = {
            ruff = { format = { enable = false } },
        },
    }

    vim.lsp.config["perl-lsp"] = {
        cmd = { "perllsp" },
        filetypes = { "perl" },
        root_markers = { { "cpanfile", "Makefile.PL", "Build.PL" }, unpack(root_markers) },
        capabilities = capabilities,
        on_attach = on_attach,
    }

    vim.lsp.config.bashls = {
        cmd = { "bash-language-server", "start" },
        filetypes = { "sh", "bash", "zsh" },
        root_markers = { ".git" },
        capabilities = capabilities,
        on_attach = on_attach,
    }

    vim.lsp.config.lua_ls = {
        cmd = { "lua-language-server" },
        filetypes = { "lua" },
        root_markers = { ".luarc.json", ".luacheckrc", ".stylua.toml", ".git" },
        capabilities = capabilities,
        on_attach = on_attach,
        settings = {
            Lua = {
                runtime = { version = "LuaJIT" },
                diagnostics = { globals = { "vim" } },
                workspace = {
                    library = vim.api.nvim_get_runtime_file("", true),
                    checkThirdParty = false,
                },
            },
        },
    }

    vim.lsp.config.jsonls = {
        cmd = { "vscode-json-language-server", "--stdio" },
        filetypes = { "json", "jsonc" },
        root_markers = { ".git" },
        capabilities = capabilities,
        on_attach = on_attach,
    }

    vim.lsp.config.yamlls = {
        cmd = { "yaml-language-server", "--stdio" },
        filetypes = { "yaml", "yml" },
        root_markers = { ".git" },
        capabilities = capabilities,
        on_attach = on_attach,
    }

    if vim.fn.executable("slang-server") == 1 then
        vim.lsp.config["slang-server"] = {
            cmd = { "slang-server" },
            filetypes = { "verilog", "systemverilog" },
            root_markers = { ".git", ".slang" },
            capabilities = capabilities,
            on_attach = on_attach,
        }
    end

    vim.lsp.config.clangd = {
        cmd = { "clangd" },
        filetypes = { "c", "cpp", "objc", "objcpp", "cuda" },
        root_markers = { ".clangd", "compile_commands.json", ".git" },
        capabilities = capabilities,
        on_attach = on_attach,
    }

    vim.lsp.config.verible = {
        cmd = { "verible-verilog-ls", "--rules_config_search" },
        filetypes = { "verilog", "systemverilog" },
        root_markers = { ".git" },
        capabilities = capabilities,
        on_attach = function(client, bufnr)
            client.server_capabilities.definitionProvider = false
            client.server_capabilities.referencesProvider = false
            client.server_capabilities.implementationProvider = false
            client.server_capabilities.typeDefinitionProvider = false
            on_attach(client, bufnr)
        end,
    }

    local servers = { "pyright", "ruff", "perl-lsp", "bashls", "lua_ls", "jsonls", "yamlls", "verible", "clangd" }
    if vim.fn.executable("slang-server") == 1 then
        table.insert(servers, "slang-server")
    end
    vim.lsp.enable(servers)

    vim.diagnostic.config({
        virtual_text = false,
        signs = {
            text = {
                [vim.diagnostic.severity.ERROR] = "  ",
                [vim.diagnostic.severity.WARN] = "  ",
                [vim.diagnostic.severity.INFO] = "  ",
                [vim.diagnostic.severity.HINT] = "  ",
            },
        },
        update_in_insert = false,
        underline = true,
        severity_sort = true,
        float = {
            focusable = false,
            style = "minimal",
            border = "rounded",
            source = true,
            header = "",
            prefix = "",
        },
    })
    vim.diagnostic.enable(false)

    vim.api.nvim_create_user_command("LspStatus", function()
        local clients = vim.lsp.get_clients()
        if #clients == 0 then
            vim.notify("No active LSP clients", vim.log.levels.INFO)
            return
        end
        local lines = { "LSP Clients:" }
        for _, c in ipairs(clients) do
            local bufnrs = {}
            for b, _ in pairs(c.attached_buffers or {}) do
                table.insert(bufnrs, tostring(b))
            end
            table.insert(lines, string.format(
                "  %s | cmd: %s | bufs: [%s]",
                c.name, c.config.cmd[1] or "?", table.concat(bufnrs, ",")
            ))
        end
        vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
    end, { desc = "Show LSP client status" })
end

return M
