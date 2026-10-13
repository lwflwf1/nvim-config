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
            -- `kinds` is what the backend filters on (the requested kinds plus
            -- the container kinds, so roots survive); `selected` is the raw
            -- request, read by post_add_all_symbols to drop containers that
            -- end up with no matching descendant (VS Code-style).
            local function apply_filter(src_bufnr, kinds, selected)
                vim.b[src_bufnr].aerial_filter_kind = kinds
                vim.b[src_bufnr].aerial_filter_selected = selected
                require("aerial").refetch_symbols(src_bufnr)
            end

            -- The backend filter drops non-matching items and re-parents the
            -- rest, so a container with no matching descendant is left without
            -- children. Prune those, keeping only the ancestors of matches.
            local function prune(items, selected)
                local out = {}
                for _, item in ipairs(items) do
                    item.children = prune(item.children or {}, selected)
                    if selected[item.kind] or #item.children > 0 then
                        out[#out + 1] = item
                    end
                end
                return out
            end

            local function src_bufnr()
                return vim.api.nvim_buf_get_var(vim.api.nvim_get_current_buf(), "source_buffer")
            end

            local containers = {
                systemverilog = { "Class", "Interface", "Module", "Package", "Program" },
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

            local function open_kind_picker(source_bufnr)
                local items = {}
                -- One entry per kind; pick several with <Tab>.
                local kinds = {
                    "Module", "Interface", "Package", "Class", "Constructor",
                    "Function", "Property", "Constraint", "AssertProperty",
                    "Clocking", "Block", "Covergroup", "Variable", "Net", "Constant",
                    "InputPort", "OutputPort", "InoutPort", "Port",
                }
                for _, k in ipairs(kinds) do
                    table.insert(items, { text = k, kind = k })
                end
                Snacks.picker.pick({
                    items = items,
                    title = "Aerial kind filter (<Tab> to multi-select)",
                    layout = { preset = "select", style = "minimal" },
                    format = "text",
                    actions = {
                        confirm = function(picker, _)
                            picker:close()
                            local picked = {}
                            for _, it in ipairs(picker:selected({ fallback = true })) do
                                picked[#picked + 1] = it.kind
                            end
                            if #picked == 0 then
                                apply_filter(source_bufnr, nil, nil)
                            else
                                apply_filter(source_bufnr, vim.list_extend(vim.deepcopy(container_kinds(source_bufnr)), picked), picked)
                            end
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
                    "Variable", "Net", "Property", "Constraint", "AssertProperty",
                    "Clocking", "Covergroup", "Constant",
                    "InputPort", "OutputPort", "InoutPort", "Port",
                },
                -- A port re-declared internally (`input foo;` ... `wire foo;`)
                -- would show up twice; keep the Port symbol, drop the signal.
                post_parse_symbol = function(bufnr, item, ctx)
                    if item.kind ~= "Variable" and item.kind ~= "Net" then
                        return nil
                    end
                    if require("box.sv").port_names(bufnr, ctx.syntax_tree)[item.name] then
                        return false
                    end
                end,
                -- VS Code-style container pruning: keep a container only when a
                -- matching descendant survived the backend filter. Skipped for
                -- the default and show-all modes (no raw selection recorded).
                post_add_all_symbols = function(bufnr, items, _)
                    local sel = vim.b[bufnr].aerial_filter_selected
                    if type(sel) ~= "table" then
                        return items
                    end
                    local selected = {}
                    for _, k in ipairs(sel) do
                        selected[k] = true
                    end
                    return prune(items, selected)
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
                    Net            = "󱕆 " ,
                },
                show_guides = false,
                keymaps = {
                    ["sa"] = {
                        callback = function()
                            apply_filter(src_bufnr(), false, false)
                        end,
                        desc = "Show all symbols",
                    },
                    ["sr"] = {
                        callback = function()
                            apply_filter(src_bufnr(), nil, nil)
                        end,
                        desc = "Restore default",
                    },
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
            vim.lsp.protocol.SymbolKind.Net = 36
            require("aerial").setup(opts)
        end,
    },
}
