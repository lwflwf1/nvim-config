local M = {}

local DEFAULTS = {}

local opts = {}

local pending = ""

local active

local function enter(prefix, keys)
    pending = ""

    active = {
        prefix = prefix,
        keys = keys,
        backup_maps = {}
    }

    for _, k in ipairs(keys) do
        active.backup_maps[k] = vim.fn.maparg(k, "n", false, true)
        vim.keymap.set("n", k, prefix..k, { buf = 0, remap = true, nowait = true })
    end
end

local function leave()
    if not active then
        pending = ""
        return
    end
    for k, m in pairs(active.backup_maps) do
        pcall(vim.keymap.del, "n", k, {buf = 0})
        if next(m) then
            vim.fn.mapset(m)
        end
    end
    active = nil
    pending = ""
end

local function detect()
    local wait = false
    for prefix, v in pairs(opts.mappings or {}) do
        for _, k in ipairs(v.keys or {}) do
            local seq = vim.keycode(prefix..k)
            if #pending >= #seq and pending:sub(-#seq) == seq then
                return prefix
            end
            if vim.startswith(seq, pending) then
                wait = true
            end
        end
    end
    return wait and "wait" or "drop"
end

local function handle(_, typed)
    if typed == "" then
        return
    end

    local t = vim.fn.keytrans(typed)
    if t:find("Mouse") or t:find("Drag") or t:find("ScrollWheel") then
        return
    end

    if vim.api.nvim_get_mode().mode ~= "n" then
        leave()
        return
    end

    if active then
        for _, k in ipairs(active.keys) do
            if vim.startswith(t, k) then
                return
            end
        end
        leave()
        return
    end

    pending = pending .. typed

    local state = detect()

    if state == "wait" then
        return
    elseif state == "drop" then
        pending = ""
    else
        enter(state, opts.mappings[state].keys)
    end

end

local reported = false

local function safe_handle(key, typed)
    local ok, err = pcall(handle, key, typed)
    if not ok then
        active = nil
        pending = ""
        if not reported then
            reported = true
            vim.schedule(function()
                vim.notify("sticky: " .. err, vim.log.levels.ERROR)
            end)
        end
    end
end

function M.setup(o)
    opts = vim.tbl_deep_extend("force", DEFAULTS, o or {})
    local ns = vim.api.nvim_create_namespace("box_sticky")
    vim.on_key(safe_handle, ns)

    local aug = vim.api.nvim_create_augroup("box_sticky", { clear = true })
    vim.api.nvim_create_autocmd("BufLeave", {
        group = aug,
        callback = function() leave() end,
    })
end

function M.status()
    return active and active.prefix or nil
end

return M
