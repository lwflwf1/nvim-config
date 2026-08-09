local M = {}
local root_markers = require("config.root_markers")

---@type table<string,string> server name -> mason package name
--- Servers without a mapping are skipped by :ToolInstall. Excluded here:
--- - `perl-lsp` ships as the `perllsp` binary, not a mason package
---   (installed via Strawberry/APK, not mason).
--- - `verible` uses the standalone install under
---   AppData\Local\Programs\verible (PATH); the current mason win64 build
---   v0.0-4084 crashes on startup (0xC0000005), so it is not managed by mason.
M.tool_mapping = {
    pyrefly = "pyrefly",
    ruff = "ruff",
    bashls = "bash-language-server",
    lua_ls = "lua-language-server",
    jsonls = "vscode-json-languageserver",
    yamlls = "yaml-language-server",
    clangd = "clangd",
    rust_analyzer = "rust-analyzer",
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

    local function lsp_jump(method)
        return function()
            local word = vim.fn.expand("<cword>")
            if word == "" then return end

            local clients = vim.lsp.get_clients({ bufnr = 0 })
            if #clients == 0 then
                vim.notify((fallback_messages[method] or "No results found") .. ": " .. word, vim.log.levels.INFO)
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
                    vim.notify((fallback_messages[method] or "No results found") .. ": " .. word, vim.log.levels.INFO)
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
                    local locations = (res and res.result) or nil
                    if locations then
                        if not vim.islist(locations) then
                            locations = { locations }
                        end
                        local items = vim.lsp.util.locations_to_items(locations, client.offset_encoding)
                        vim.list_extend(all_items, items)
                    end
                end
                if next(all_items) then
                    vim.fn.setqflist(all_items)
                    vim.api.nvim_command("Trouble qflist open")
                else
                    vim.notify((fallback_messages[method] or "No results found") .. ": " .. word, vim.log.levels.INFO)
                end
            end)
        end
    end

    vim.keymap.set("n", "gd", lsp_jump("textDocument/definition"),
        { silent = true, noremap = true, desc = "Go to definition" })
    vim.keymap.set("n", "grr", lsp_jump("textDocument/references"),
        { silent = true, noremap = true, desc = "Go to references" })
    vim.keymap.set("n", "gri", lsp_jump("textDocument/implementation"),
        { silent = true, noremap = true, desc = "Go to implementation" })
    vim.keymap.set("n", "grt", lsp_jump("textDocument/typeDefinition"),
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
        -- Jump to next/prev diagnostic and show it in a float.
        -- vim.diagnostic.jump's on_jump callback is scheduled internally to
        -- run after the jump's own cursor move, so the float survives the
        -- jump's CursorMoved. snacks.scroll smooth-scrolling would otherwise
        -- animate the view across pages and position the float off-screen, so
        -- it is temporarily disabled for this buffer (vim.buf[buf].snacks_scroll
        -- filter); with a static view the float opens anchored to the target.
        -- Rapid presses are safe: each press re-disables the flag, and only
        -- the last one restores the original value and opens the float.
        local scroll_gen = {}      -- bufnr -> press generation
        local scroll_orig = {}     -- bufnr -> original snacks_scroll value
        local scroll_captured = {} -- bufnr -> original value captured
        local function jump_diag(count)
            local bufnr = vim.api.nvim_get_current_buf()
            scroll_gen[bufnr] = (scroll_gen[bufnr] or 0) + 1
            local gen = scroll_gen[bufnr]
            if not scroll_captured[bufnr] then
                scroll_captured[bufnr] = true
                scroll_orig[bufnr] = vim.b[bufnr].snacks_scroll
            end
            vim.b[bufnr].snacks_scroll = false
            local diag = vim.diagnostic.jump({
                count = count,
                on_jump = function(d, b)
                    if scroll_gen[b] ~= gen then return end -- superseded by a new press
                    vim.b[b].snacks_scroll = scroll_orig[b]
                    scroll_captured[b] = nil
                    scroll_orig[b] = nil
                    if not d then return end
                    vim.cmd("normal! zz") -- center cursor line (snacks scroll still disabled, so no animation)
                    vim.diagnostic.open_float({ bufnr = b, pos = { d.lnum, d.col } })
                end,
            })
            if not diag and scroll_gen[bufnr] == gen then
                vim.b[bufnr].snacks_scroll = scroll_orig[bufnr]
                scroll_captured[bufnr] = nil
                scroll_orig[bufnr] = nil
            end
        end
        vim.keymap.set("n", "grj", function() jump_diag(1) end, bopts("Next diagnostic"))
        vim.keymap.set("n", "grk", function() jump_diag(-1) end, bopts("Prev diagnostic"))
    end

    vim.lsp.config.pyrefly = {
        cmd = { "pyrefly", "lsp" },
        filetypes = { "python" },
        root_markers = { "pyproject.toml", "setup.py", "setup.cfg", "requirements.txt", ".git" },
        capabilities = capabilities,
        on_attach = on_attach,
        settings = {
            python = {
                pyrefly = {
                    typeCheckingMode = "default",
                },
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
            -- hover/definition/completion are pyrefly's job.
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
        settings = {
            json = {
                schemas = json_schemas(),
                validate = { enable = true },
            },
        },
    }

    vim.lsp.config.yamlls = {
        cmd = { "yaml-language-server", "--stdio" },
        filetypes = { "yaml", "yml" },
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

    vim.lsp.config.verible = {
        cmd = { "verible-verilog-ls", "--rules_config_search" },
        filetypes = { "verilog", "systemverilog" },
        root_markers = { ".git" },
        capabilities = capabilities,
        on_attach = on_attach,
    }

    vim.lsp.config.rust_analyzer = {
        cmd = { "rust-analyzer" },
        filetypes = { "rust" },
        root_markers = { "Cargo.toml", "rust-project.json", ".git" },
        capabilities = capabilities,
        on_attach = on_attach,
        settings = {
            ["rust-analyzer"] = {
                check = {
                    command = "clippy",
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
    }

    local servers = { "pyrefly", "ruff", "perl-lsp", "bashls", "lua_ls", "jsonls", "yamlls", "verible", "clangd", "rust_analyzer" }
    vim.lsp.enable(servers)
    M.servers = servers

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
