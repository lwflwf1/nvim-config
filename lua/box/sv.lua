-- SystemVerilog helpers shared by the aerial and dropbar specs.
local M = {}

---@type table<integer, { tick: integer, names: table<string, true> }>
local cache = {}

-- Drop a buffer's entry when it goes away (bufnrs are not reused, but this
-- keeps the table from growing over a long session).
vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = vim.api.nvim_create_augroup("box_sv_cache", { clear = true }),
    callback = function(args)
        cache[args.buf] = nil
    end,
})

local function collect(node, bufnr, names)
    for child in node:iter_children() do
        local t = child:type()
        if t == 'list_of_port_identifiers' then
            for id in child:iter_children() do
                if id:type() == 'simple_identifier' then
                    names[vim.treesitter.get_node_text(id, bufnr)] = true
                end
            end
        elseif t == 'ansi_port_declaration' then
            -- The port identifier is the direct child; the header (which may
            -- hold a user type identifier) is a separate child.
            for id in child:iter_children() do
                if id:type() == 'simple_identifier' then
                    names[vim.treesitter.get_node_text(id, bufnr)] = true
                end
            end
        else
            collect(child, bufnr, names)
        end
    end
end

---Set of port names in the buffer, so a redundant internal re-declaration of a
---port (`input foo;` ... `wire foo;`) can be hidden. Cached per changedtick.
---@param bufnr integer
---@param tree? vim.treesitter.LanguageTree
---@return table<string, true>
M.port_names = function(bufnr, tree)
    local tick = vim.b[bufnr].changedtick
    local entry = cache[bufnr]
    if entry and entry.tick == tick then
        return entry.names
    end
    if not tree then
        local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
        if ok and parser then
            tree = parser:parse()[1]
        end
    end
    local names = {}
    if tree then
        collect(tree:root(), bufnr, names)
    end
    cache[bufnr] = { tick = tick, names = names }
    return names
end

return M
