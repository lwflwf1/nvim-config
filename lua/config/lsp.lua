local M = {}
local root_markers = require("config.project").markers

---@type table<string,string> server name -> mason package name
--- Servers without a mapping are skipped by :ToolInstall. Excluded here:
--- - `perl-lsp` ships as the `perllsp` binary, not a mason package
---   (installed via Strawberry/APK, not mason).
--- - `verible` uses the standalone install under
---   AppData\Local\Programs\verible (PATH); the current mason win64 build
---   v0.0-4084 crashes on startup (0xC0000005), so it is not managed by mason.
M.tool_mapping = {
    ty = "ty",
    ruff = "ruff",
    bashls = "bash-language-server",
    lua_ls = "lua-language-server",
    jsonls = "json-lsp",
    yamlls = "yaml-language-server",
    clangd = "clangd",
}

---@return table schemas list, or {} if schemastore.nvim is unavailable
local function json_schemas()
    local ok, schemastore = pcall(require, "schemastore")
    if not ok then
        return {}
    end
    local ok2, schemas = pcall(function()
        return schemastore.json.schemas()
    end)
    return ok2 and schemas or {}
end

local function yaml_schemas()
    local ok, schemastore = pcall(require, "schemastore")
    if not ok then
        return {}
    end
    local ok2, schemas = pcall(function()
        return schemastore.yaml.schemas()
    end)
    return ok2 and schemas or {}
end

function M.setup()
    local capabilities = vim.lsp.protocol.make_client_capabilities()
    capabilities = require("blink.cmp").get_lsp_capabilities(capabilities)
    capabilities.textDocument.foldingRange = {
        dynamicRegistration = false,
        lineFoldingOnly = true,
    }

    local fallback_messages = {
        ["textDocument/definition"] = "No definition found",
        ["textDocument/references"] = "No references found",
        ["textDocument/implementation"] = "No implementation found",
        ["textDocument/typeDefinition"] = "No type definition found",
    }

    local method_to_cap = {
        ["textDocument/definition"] = "definitionProvider",
        ["textDocument/references"] = "referencesProvider",
        ["textDocument/implementation"] = "implementationProvider",
        ["textDocument/typeDefinition"] = "typeDefinitionProvider",
    }

    local glance_methods = {
        ["textDocument/definition"] = "definitions",
        ["textDocument/references"] = "references",
        ["textDocument/implementation"] = "implementations",
        ["textDocument/typeDefinition"] = "type_definitions",
    }

    local function glance_jump(method)
        local word = vim.fn.expand("<cword>")
        local clients = vim.lsp.get_clients({ bufnr = 0 })
        local cap = method_to_cap[method]
        for _, client in ipairs(clients) do
            if (client.server_capabilities or {})[cap] then
                -- Glance (dnlhc/glance.nvim): list + preview UI. It is lazy-loaded
                -- via `cmd`, and this triggers its load + the :Glance command.
                vim.cmd("Glance " .. glance_methods[method])
                return
            end
        end
        -- No client supports it: gd falls back to the built-in gd (local
        -- declaration search); the rest notify.
        if method == "textDocument/definition" then
            vim.cmd("normal! gd")
        else
            vim.notify((fallback_messages[method] or "No results found") .. ": " .. word, vim.log.levels.INFO)
        end
    end

    vim.keymap.set("n", "gd", function() glance_jump("textDocument/definition") end,
        { silent = true, noremap = true, desc = "Go to definition" })
    vim.keymap.set("n", "grr", function() glance_jump("textDocument/references") end,
        { silent = true, noremap = true, desc = "Go to references" })
    vim.keymap.set("n", "gri", function() glance_jump("textDocument/implementation") end,
        { silent = true, noremap = true, desc = "Go to implementation" })
    vim.keymap.set("n", "grt", function() glance_jump("textDocument/typeDefinition") end,
        { silent = true, noremap = true, desc = "Go to type definition" })

    local on_attach = function(client, bufnr)
        local bopts = function(desc)
            return { buffer = bufnr, silent = true, noremap = true, desc = desc }
        end

        vim.keymap.set("n", "K", function()
            local winid = require("ufo").peekFoldedLinesUnderCursor()
            if not winid then
                vim.lsp.buf.hover()
            end
        end, bopts("Peek fold or LSP hover"))
        vim.keymap.set("n", "gk", vim.lsp.buf.signature_help, bopts("Signature help"))
        vim.keymap.set("n", "grd", vim.diagnostic.open_float, bopts("Diagnostic float"))
        -- Jump to next/prev diagnostic and center the view. jump() opens no
        -- float by default; the scroll animation settles on the zz'd view.
        local function jump_diag(count)
            vim.diagnostic.jump({ count = count })
            vim.cmd("normal! zz")
        end
        vim.keymap.set("n", "]d", function() jump_diag(1) end, bopts("Next diagnostic"))
        vim.keymap.set("n", "[d", function() jump_diag(-1) end, bopts("Prev diagnostic"))
    end

    vim.lsp.config.ty = {
        cmd = { "ty", "server" },
        filetypes = { "python" },
        root_markers = { "pyproject.toml", "setup.py", "setup.cfg", "requirements.txt", ".git" },
        capabilities = capabilities,
        on_attach = on_attach,
        settings = {
            ty = {
                diagnosticMode = "workspace",
            },
        },
    }

    vim.lsp.config.ruff = {
        cmd = { "ruff", "server" },
        filetypes = { "python" },
        root_markers = { "pyproject.toml", "setup.py", "setup.cfg", "requirements.txt", ".git" },
        capabilities = capabilities,
        on_attach = function(client, bufnr)
            -- Ruff only serves lint diagnostics + lint code actions;
            -- hover/definition/completion are ty's job.
            client.server_capabilities.hoverProvider = false
            on_attach(client, bufnr)
        end,
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
                diagnostics = { globals = { "vim", "Snacks" } },
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
        settings = {
            json = {
                schemas = json_schemas(),
                validate = { enable = true },
            },
        },
    }

    vim.lsp.config.yamlls = {
        cmd = { "yaml-language-server", "--stdio" },
        filetypes = { "yaml" },
        root_markers = { ".git" },
        capabilities = capabilities,
        on_attach = on_attach,
        settings = {
            yaml = {
                schemaStore = {
                    -- Disable built-in schemaStore since we use schemastore.nvim
                    enable = false,
                    -- Avoid TypeError: Cannot read properties of undefined (reading 'length')
                    url = "",
                },
                schemas = yaml_schemas(),
            },
        },
    }

    vim.lsp.config.clangd = {
        cmd = { "clangd" },
        filetypes = { "c", "cpp", "objc", "objcpp", "cuda" },
        root_markers = { ".clangd", "compile_commands.json", ".git" },
        capabilities = capabilities,
        on_attach = on_attach,
    }

    local servers = { "ty", "ruff", "perl-lsp", "bashls", "lua_ls", "jsonls", "yamlls", "clangd" }
    vim.lsp.enable(servers)
    M.servers = servers

    -- rustaceanvim: official vim.lsp.config channel for its server options.
    -- rustaceanvim deep-merges this config into its own client config, so
    -- blink.cmp's completion capabilities coexist with rust-analyzer's
    -- experimental features (hoverActions, ssr, codeActionGroup, ...).
    vim.lsp.config("rust-analyzer", {
        capabilities = vim.tbl_deep_extend(
            "force",
            {},
            require("blink.cmp").get_lsp_capabilities(vim.lsp.protocol.make_client_capabilities())
        ),
    })

    vim.diagnostic.config({
        virtual_text = true,
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

    M.on_attach = on_attach
end

return M
