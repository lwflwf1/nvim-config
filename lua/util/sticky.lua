local M

local state = {}

local DEFAULTS = {

}

function M.setup(opts)
    clear()
    opts = vim.tbl_deep_extend("force", DEFAULTS, opts or {})
    state.enabled = opts.enabled
    if not state.ns then
        state.ns = vim.api.nvim_create_namespace("sticky")
        vim.on_key(function (_, typed) handle(typed or "") end, state.ns)
    end
end

local function handle(typed)
    if typed == "" then
        return
    end
    if vim.fn.mode() ~= "n" then
        return
    end

    local kt = vim.fn.keytrans(typed)
    if kt:find("ScrollWheel",1,true) or kt:find("Mouse",1,true) then
        return
    end

    if to_raw(kt) == to_raw("<Esc>") then
        clear()
        return
    end

    if state.active then
        feedkey(typed)
    else
        state.typed = (state.typed..typed):sub(-64)
        prefix = match_prefix(state.typed, vim.tbl_keys(opts.prefix))
        if prefix then
            descend(prefix)
        end
    end
end



---match prefix of key
---@param typed string
---@return string|nil
local function match_prefix(typed, candidates)
    local keys = vim.fn.keytrans(typed)
    for _, k in ipairs(candidates) do
        if keys:sub(-#k) == k then
            return k
        end
    end
    return nil
end

local function set_keymap()

end

local function descend(prefix)
    state.active = true
    if not state.prefix[prefix] then
        state.prefix[prefix] = scan(prefix)
    end
    frame = {prefix}
    table.insert(state.stack, 1, frame)
    set_keymap()
end

local function ascend()
    if #state.stack == 0 then
        clear()
        return
    end
    table.remove(state.stack, 1)
    if #state.stack == 0 then
        clear()
        return
    end
end

local function clear()
    state = {
        active = false
        ns = nil,
        typed = nil,
        frame_stack = {}
    }
end

local function to_raw(key)
    return vim.api.nvim_replace_termcodes(key, true, true, true)
end

local function scan(prefix)
    local raw_prefix = to_raw(prefix)
    local maps = vim.api.nvim_get_keymap("n")
    vim.list_extend(maps, vim.api.nvim_buf_get_keymap(0, "n"))
    local all = {}
    for _, m, in ipairs(maps) do
        if m.lhs:sub(1,6) ~= "<Plug>" and m.lhs:sub(1,5) ~= "<SNR>" then
            local raw_lhs = to_raw(m.lhs)
            if #raw_lhs > #raw_prefix and raw_lhs:sub(1:#raw_prefix) == raw_prefix then
                all[#all+1] = {
                    lhs = m.lhs
                    raw = raw_lhs:sub(#raw_prefix+1),
                    keys = split_keys(m.lhs:sub(#prefix+1))
                    mapping = m
                }
            end
        end
    end
    local children, by_key = {}, {}
    for _, item in ipairs(all) do
        local k = item.keys[1]
        c = by_key[k]
        if not c then
            c = {
                key = k,
                raw = to_raw(k),
                lhs = prefix..k,
                mapping = nil,
                kind = "leaf"
            }
            by_key[k] = c
            children[#children+1] = c
        end
        if #item.keys == 1 then
            c.mapping = item.mapping
        else
            c.kind = "group"
        end
    end

    return {all = all, children = children}
end

local function nearest_prefix(prefix, item)
    return prefix..table.concat(item.keys, "", 1, #item.keys-1)
end

return M
