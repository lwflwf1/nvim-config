return {
    {
        "stevearc/aerial.nvim",
        cmd = { "AerialToggle", "AerialOpen", "AerialNavToggle" },
        keys = {
            { "<leader>lo", "<cmd>AerialToggle!<CR>", desc = "Toggle aerial outline" },
            { "<leader>lO", "<cmd>AerialNavToggle<CR>", desc = "Toggle aerial nav window" },
            { "<leader>fs", function() require("aerial").snacks_picker() end, desc = "Aerial symbols (snacks)" },
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

            -- Port kinds stay as 4 separate picker entries, but the "Port"
            -- entry keeps every direction at once (they are distinct kinds
            -- internally, so each direction can carry its own icon).
            local port_kinds = { "InputPort", "OutputPort", "InoutPort", "Port" }

            local function open_kind_picker(source_bufnr)
                local items = {}
                local kinds = {
                    { "Module" },
                    { "Interface" },
                    { "Package" },
                    { "Class" },
                    { "Constructor" },
                    { "Function" },
                    { "Property" },
                    { "Constraint" },
                    { "AssertProperty" },
                    { "Clocking" },
                    { "Block" },
                    { "Covergroup" },
                    { "Variable" },
                    { "InputPort" },
                    { "OutputPort" },
                    { "InoutPort" },
                    { "Port", port_kinds },
                }
                for _, spec in ipairs(kinds) do
                    table.insert(items, { text = spec[1], kinds = spec[2] or { spec[1] } })
                end
                Snacks.picker.pick({
                    items = items,
                    title = "Aerial kind filter",
                    layout = { preset = "select", style = "minimal" },
                    format = "text",
                    actions = {
                        confirm = function(picker, item)
                            picker:close()
                            apply_filter(source_bufnr, item and vim.list_extend(vim.deepcopy(container_kinds(source_bufnr)), item.kinds) or nil)
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
                    "InputPort", "OutputPort", "InoutPort", "Port",
                },
                -- A port re-declared internally (`input foo;` ... `wire foo;`)
                -- would show up twice; keep the Port symbol, drop the Variable.
                post_parse_symbol = function(bufnr, item, ctx)
                    if item.kind ~= "Variable" then
                        return nil
                    end
                    if require("box.sv").port_names(bufnr, ctx.syntax_tree)[item.name] then
                        return false
                    end
                end,
                icons = {
                    Clocking       = "",
                    Block          = "󰦮",
                    Covergroup     = "󰓾",
                    AssertProperty = "",
                    Constraint     = "󰗴",
                    InputPort      = " ",
                    OutputPort     = " ",
                    InoutPort      = " ",
                    Port           = "󱘖 ",
                },
                show_guides = true,
                keymaps = {
                    ["sf"] = filter({ "Function", "Constructor" }, "Filter: Functions/Constructor"),
                    ["sc"] = filter({ "Class", "Interface", "Module", "Package" }, "Filter: Class/Interface/Module/Package"),
                    ["sp"] = filter({ "Property", "Constraint", "AssertProperty" }, "Filter: Property/Constraint/AssertProperty"),
                    ["sv"] = filter({ "Variable" }, "Filter: Variable"),
                    ["sP"] = filter(port_kinds, "Filter: Ports"),
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
            vim.lsp.protocol.SymbolKind.Port = 32
            vim.lsp.protocol.SymbolKind.InputPort = 33
            vim.lsp.protocol.SymbolKind.OutputPort = 34
            vim.lsp.protocol.SymbolKind.InoutPort = 35
            require("aerial").setup(opts)
        end,
    },
}
