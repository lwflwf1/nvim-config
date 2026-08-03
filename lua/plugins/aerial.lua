return {
    {
        "stevearc/aerial.nvim",
        cmd = { "AerialToggle", "AerialOpen", "AerialNavToggle" },
        dependencies = {
            "ibhagwan/fzf-lua",
        },
        keys = {
            { "<leader>lo", "<cmd>AerialToggle!<CR>", desc = "Aerial outline" },
            { "<leader>lO", "<cmd>AerialNavToggle<CR>", desc = "Aerial nav window" },
            { "<leader>fs", function() require("aerial").fzf_lua_picker() end, desc = "Aerial symbols (fzf)" },
            { "]s", function() require("aerial").next() end, desc = "Next symbol" },
            { "[s", function() require("aerial").prev() end, desc = "Prev symbol" },
        },
        opts = function()
            local function apply_filter(src_bufnr, kinds)
                vim.b[src_bufnr].aerial_filter_kind = kinds
                require("aerial").refetch_symbols(src_bufnr)
            end

            local function src_bufnr()
                return vim.api.nvim_buf_get_var(vim.api.nvim_get_current_buf(), "source_buffer")
            end

            local containers = {
                systemverilog = { "Class", "Interface", "Module", "Package" },
                python = { "Class", "Module" },
                perl = { "Package" },
                cpp = { "Class", "Struct", "Namespace" },
                c = { "Struct", "Namespace" },
                lua = { "Module", "Class" },
                rust = { "Module", "Struct", "Enum", "Trait", "Impl" },
                typescript = { "Class", "Interface", "Namespace", "Enum" },
                javascript = { "Class", "Namespace" },
                _ = { "Class", "Interface", "Module", "Package", "Namespace" },
            }

            local function container_kinds(bufnr)
                return containers[vim.bo[bufnr or src_bufnr()].filetype] or containers["_"]
            end

            local function filter(kinds, desc)
                return {
                    callback = function()
                        local sb = src_bufnr()
                        local merged
                        if kinds == false then
                            merged = false
                        else
                            merged = kinds and vim.list_extend(vim.deepcopy(kinds), container_kinds(sb)) or nil
                        end
                        apply_filter(sb, merged)
                    end,
                    desc = desc or "",
                }
            end

            local function open_kind_picker(source_bufnr)
                local items = {}
                local kinds = { "Module", "Interface", "Package", "Class", "Constructor", "Function", "Property", "Constraint", "AssertProperty", "Clocking", "Block", "Covergroup", "Variable" }
                for _, k in ipairs(kinds) do
                    table.insert(items, { text = k, kind = k })
                end
                Snacks.picker.pick({
                    items = items,
                    title = "Aerial kind filter",
                    layout = { preset = "select", style = "minimal" },
                    format = "text",
                    actions = {
                        confirm = function(picker, item)
                            picker:close()
                            apply_filter(source_bufnr, item and vim.list_extend(vim.deepcopy(container_kinds(source_bufnr)), { item.kind }) or nil)
                        end,
                    },
                })
            end

            return {
                attach_mode = "global",
                autojump = true,
                highlight_on_hover = true,
                highlight_on_jump = false,
                nerd_font = true,
                manage_folds = true,
                link_folds_to_tree = true,
                link_tree_to_folds = true,
                backends = { "treesitter", "lsp", "markdown" },
                layout = {
                    default_direction = "prefer_right",
                    max_width = { 40, 0.2 },
                    min_width = 10,
                },
                filter_kind = {
                    "Class", "Constructor", "Function", "Interface", "Module",
                    "Variable", "Property", "Constraint", "AssertProperty",
                    "Clocking", "Covergroup",
                },
                icons = {
                    Clocking       = "",
                    Block          = "󰦮",
                    Covergroup     = "󰓾",
                    AssertProperty = "",
                    Constraint     = "󰗴",
                },
                show_guides = true,
                keymaps = {
                    ["sf"] = filter({ "Function", "Constructor" }, "Filter: Functions/Constructor"),
                    ["sc"] = filter({ "Class", "Interface", "Module", "Package" }, "Filter: Class/Interface/Module/Package"),
                    ["sp"] = filter({ "Property", "Constraint", "AssertProperty" }, "Filter: Property/Constraint/AssertProperty"),
                    ["sv"] = filter({ "Variable" }, "Filter: Variable"),
                    ["so"] = filter({ "Clocking", "Covergroup" }, "Filter: Clocking/Covergroup"),
                    ["sb"] = filter({"Block"}, "Filter: Block"),
                    ["sa"] = filter(false, "Show all symbols"),
                    ["sr"] = filter(nil, "Restore default"),
                    ["ss"] = {
                        callback = function()
                            open_kind_picker(src_bufnr())
                        end,
                        desc = "Select kinds",
                    },
                },
            }
        end,
        config = function(_, opts)
            vim.lsp.protocol.SymbolKind.Constraint = 27
            vim.lsp.protocol.SymbolKind.Clocking = 28
            vim.lsp.protocol.SymbolKind.Block = 29
            vim.lsp.protocol.SymbolKind.Covergroup = 30
            vim.lsp.protocol.SymbolKind.AssertProperty = 31
            require("aerial").setup(opts)
            vim.api.nvim_set_hl(0, "AerialLine", { link = "IncSearch", default = true })

            -- Custom kind highlights
            vim.api.nvim_set_hl(0, "AerialClockingIcon",       { link = "Special",    default = true })
            vim.api.nvim_set_hl(0, "AerialBlockIcon",          { link = "Special",    default = true })
            vim.api.nvim_set_hl(0, "AerialCovergroupIcon",     { link = "Special",    default = true })
            vim.api.nvim_set_hl(0, "AerialAssertPropertyIcon", { link = "Special",    default = true })
            vim.api.nvim_set_hl(0, "AerialConstraintIcon",     { link = "Special",    default = true })
            vim.api.nvim_set_hl(0, "AerialClocking",            { link = "AerialNormal", default = true })
            vim.api.nvim_set_hl(0, "AerialBlock",               { link = "AerialNormal", default = true })
            vim.api.nvim_set_hl(0, "AerialCovergroup",          { link = "AerialNormal", default = true })
            vim.api.nvim_set_hl(0, "AerialAssertProperty",      { link = "AerialNormal", default = true })
        end,
    },
}
