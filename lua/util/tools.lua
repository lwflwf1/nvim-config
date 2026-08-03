local M = {}

--- Collect mason package names for every LSP server declared in config.lsp
--- and present in M.tool_mapping (servers without a mapping, e.g. the
--- manually-installed `perl-lsp`, are skipped as they are not mason packages).
local function collect_lsp_packages()
    local packages = {}
    local ok, lsp = pcall(require, "config.lsp")
    if not ok then
        return packages
    end
    for _, server in ipairs(lsp.servers or {}) do
        local pkg = lsp.tool_mapping[server]
        if pkg then
            packages[#packages + 1] = pkg
        end
    end
    return packages
end

--- Formatter name -> mason package mapping for the formatters we own.
--- `rustfmt` is a rustup component, and `perltidy` is a Strawberry/Perl
--- distribution tool; neither is a mason package -> silently skipped.
local FORMATTER_MAPPING = {
    stylua = "stylua",
    ruff_format = "ruff",
    prettierd = "prettierd",
    prettier = "prettier",
    ["verible-verilog-format"] = "verible",
}

--- Formatters skipped from the manifest: present in conform but installed
--- outside of mason.
local SKIP_FORMATTERS = { rustfmt = true, perltidy = true }

--- Collect mason package names for the formatters configured in formatter.lua.
local function collect_formatter_packages()
    local packages = {}
    local ok, spec = pcall(require, "plugins.formatter")
    if not ok then
        return packages
    end
    for _, block in ipairs(spec or {}) do
        if type(block) == "table" then
            local opts = type(block.opts) == "function" and block.opts() or block.opts
            local fbf = type(opts) == "table" and opts.formatters_by_ft or {}
            if type(fbf) == "table" then
                for _, formatters in pairs(fbf) do
                    for _, name in ipairs(formatters) do
                        if not SKIP_FORMATTERS[name] then
                            local pkg = FORMATTER_MAPPING[name] or name
                            packages[#packages + 1] = pkg
                        end
                    end
                end
            end
        end
    end
    return packages
end

-- Every tool referenced by the config (deduplicated). Single source of truth.
M.tools = function()
    local seen, ordered = {}, {}
    for _, pkg in ipairs(collect_lsp_packages()) do
        if not seen[pkg] then
            seen[pkg] = true
            ordered[#ordered + 1] = pkg
        end
    end
    for _, pkg in ipairs(collect_formatter_packages()) do
        if not seen[pkg] then
            seen[pkg] = true
            ordered[#ordered + 1] = pkg
        end
    end
    return ordered
end

--- Ensure the mason plugin is loaded (it is lazily loaded via VeryLazy).
--- @return boolean ok
--- @return table? registry  the mason-registry module
local function ensure_mason()
    local ok, registry = pcall(require, "mason-registry")
    if ok then
        return true, registry
    end
    local lazy_ok = pcall(require, "lazy")
    if lazy_ok then
        -- short name for mason-org/mason.nvim
        pcall(function() require("lazy").load({ plugins = { "mason.nvim" } }) end)
    end
    return pcall(require, "mason-registry")
end

local function registry_package(name)
    local ok, registry = ensure_mason()
    if not ok then
        return nil
    end
    local ok2, pkg = pcall(function() return registry.get_package(name) end)
    return ok2 and pkg or nil
end

--- Check if a treesitter parser for `lang` is currently installed.
local function has_parser(lang)
    local ok_modules, parsers = pcall(require, "nvim-treesitter.parsers")
    if ok_modules and parsers.has_parser then
        return parsers.has_parser(lang)
    end
    -- Fallback: native API on a scratch-ish nil buffer
    local ok, _ = pcall(vim.treesitter.get_parser, 0, lang)
    return ok
end

--- :ToolInstall — install missing tools from the derived manifest,
--- plus missing tree-sitter parsers.
function M.install()
    -- 1) Mason tools referenced by the config
    local to_install, unknown = {}, {}
    for _, pkg in ipairs(M.tools()) do
        local resolved = registry_package(pkg)
        if not resolved then
            unknown[#unknown + 1] = pkg
        elseif not resolved:is_installed() then
            to_install[#to_install + 1] = pkg
        end
    end
    if #to_install > 0 then
        vim.cmd("MasonInstall " .. table.concat(to_install, " "))
        table.sort(to_install)
        vim.notify("ToolInstall: installing " .. table.concat(to_install, ", "), vim.log.levels.INFO)
    elseif #unknown > 0 then
        vim.notify("ToolInstall: unknown packages in mason registry: " .. table.concat(unknown, ", "), vim.log.levels.WARN)
    else
        vim.notify("ToolInstall: all config tools already installed", vim.log.levels.INFO)
    end
    if #unknown > 0 and #to_install == 0 then
        vim.notify("ToolInstall: skipped unknowns", vim.log.levels.WARN)
    end

    -- 2) Treesitter parsers declared in config.parsers
    local ok_parsers, parsers = pcall(require, "config.parsers")
    if ok_parsers then
        local need = {}
        for _, lang in ipairs(parsers) do
            if not has_parser(lang) then
                need[#need + 1] = lang
            end
        end
        if #need > 0 then
            vim.cmd("TSInstall " .. table.concat(need, " "))
            vim.notify("ToolInstall: installing parsers " .. table.concat(need, ", "), vim.log.levels.INFO)
        end
    end
end

--- :ToolUpdate — refresh the mason registry, reinstall any installed package
--- that has a newer version, and update all treesitter parsers.
--- Plugins are NOT touched.
function M.update()
    local ok, registry = ensure_mason()
    if not ok then
        vim.notify("ToolUpdate: mason not available, skipped", vim.log.levels.WARN)
    else
        registry.update(function(success)
            if not success then
                vim.notify("ToolUpdate: registry update failed", vim.log.levels.WARN)
                return
            end
            local outdated = {}
            for _, pkg in ipairs(registry.get_installed_packages()) do
                local installed = pkg:get_installed_version()
                local latest = pkg:get_latest_version()
                if installed ~= latest then
                    outdated[#outdated + 1] = pkg
                end
            end
            if #outdated == 0 then
                vim.notify("ToolUpdate: all mason packages up to date", vim.log.levels.INFO)
                return
            end
            for _, pkg in ipairs(outdated) do
                pkg:install()
            end
            local names = vim.tbl_map(function(pkg) return pkg.name end, outdated)
            table.sort(names)
            vim.notify("ToolUpdate: updating " .. table.concat(names, ", "), vim.log.levels.INFO)
        end)
    end

    vim.cmd("TSUpdate")
    vim.notify("ToolUpdate: updating all treesitter parsers", vim.log.levels.INFO)
end

vim.api.nvim_create_user_command("ToolInstall", function() M.install() end,
    { desc = "Install missing mason tools + treesitter parsers" })
vim.api.nvim_create_user_command("ToolUpdate", function() M.update() end,
    { desc = "Update all mason packages + treesitter parsers (no plugin updates)" })

return M