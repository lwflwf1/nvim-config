return {
    "m-demare/hlargs.nvim",
    event = "VeryLazy",
    config = function()
        require("hlargs").setup()

        -- Add SystemVerilog support via monkey-patch
        local util = require("hlargs.util")
        local sv_func_nodes = {
            "function_body_declaration",
            "task_body_declaration",
        }

        -- Patch is_supported
        local orig_is_supported = util.is_supported
        util.is_supported = function(lang)
            if lang == "systemverilog" then return true end
            return orig_is_supported(lang)
        end

        -- Patch is_function_or_catch_node via debug.getupvalue
        -- get_first_function_parent -> upvalue: is_function_or_catch_node
        local i = 1
        while true do
            local name, val = debug.getupvalue(util.get_first_function_parent, i)
            if not name then break end
            if name == "is_function_or_catch_node" then
                local orig_func = val
                debug.setupvalue(util.get_first_function_parent, i, function(filetype, node)
                    if filetype == "systemverilog" then
                        local node_type = node:type()
                        return node_type == "function_body_declaration"
                            or node_type == "task_body_declaration"
                    end
                    return orig_func(filetype, node)
                end)
                break
            end
            i = i + 1
        end
    end,
}
