local M = {}
local ns = vim.api.nvim_create_namespace("box.ts_diagnostics")

local state = {}

local DEFAULTS = {
    enabled = true,
    enabled_ft = {},
    debounce = 200,
}

local config = {}

---@type function()
local diagnose

local function cancel_timer(st)
    if st and st.timer then
        pcall(st.timer:stop)
        pcall(st.timer:close)
        st.timer = nil
    end
end

local function clear(buf)
    if vim.api.nvim_buf_is_valid(buf) then
        vim.diagnostic.set(ns, buf, {})
    end
    cancel_timer(state[buf])
    state[buf] = nil
end

function M.toggle()
    if config.enabled then
        M.disable()
    else
        M.enable()
    end
end

local function valid_buffer(buf)
    return  config.enabled
        and vim.tbl_contains(config.enabled_ft, vim.bo[buf].filetype)
        and vim.bo[buf].buftype == ""
        and vim.api.nvim_buf_is_loaded(buf)
        and vim.b[buf].ts_diagnostics_enable
        and not vim.b[buf].bigfile
        and #vim.lsp.get_clients({bufnr = buf}) == 0
end

local function detach_buffer(buf)
    local grp = vim.api.nvim_create_augroup("box.ts_diagnostics", {clear = false})
    pcall(vim.api.nvim_clear_autocmds, { group = grp, buf = buf})
    if vim.api.nvim_buf_is_valid(buf) then
        vim.b[buf].ts_diagnostics_attached = false
    end
    clear(buf)
end

local function attach_buffer(buf)
    if vim.api.nvim_buf_is_valid(buf) then
        if vim.b[buf].ts_diagnostics_enable == nil then
            vim.b[buf].ts_diagnostics_enable = true
        end
    end

    if not valid_buffer(buf) then
        detach_buffer(buf)
        return
    end

    if vim.b[buf].ts_diagnostics_attached then
        return
    end

    vim.b[buf].ts_diagnostics_attached = true
    local grp = vim.api.nvim_create_augroup("box.ts_diagnostics", {clear = false})
    vim.api.nvim_clear_autocmds({ group = grp, buf = buf})
    vim.api.nvim_create_autocmd({ "TextChanged", "InsertLeave", "BufWritePost"}, {
        group = grp,
        buffer = buf,
        desc = "treesitter diagnostic",
        callback = function (ev)
            diagnose(ev.buf)
        end
    })
end

function M.enable()
    config.enabled = true
    local grp = vim.api.nvim_create_augroup("box.ts_diagnostics", {clear = true})
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        attach_buffer(buf)
    end
    local buf = vim.api.nvim_get_current_buf()
    if vim.b[buf].ts_diagnostics_attached then
        diagnose(buf)
    end
    vim.api.nvim_create_autocmd({'BufEnter', 'LspDetach'}, {
        group = grp,
        desc = "attach treesitter diagnostic",
        callback = function (ev)
            attach_buffer(ev.buf)
            diagnose(ev.buf)
        end
    })
    vim.api.nvim_create_autocmd({'BufWipeout', 'LspAttach'}, {
        group = grp,
        desc = "dettach treesitter diagnostic",
        callback = function (ev)
            detach_buffer(ev.buf)
        end
    })
end

function M.disable()
    config.enabled = false
    for buf, _ in pairs(state) do
        detach_buffer(buf)
    end
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        detach_buffer(buf)
    end
    state = {}
    pcall(vim.api.nvim_del_augroup_by_name, "box.ts_diagnostics")
end

function M.enable_buf(buf)
    buf = buf or vim.api.nvim_get_current_buf()
    if not vim.b[buf].ts_diagnostics_enable then
        vim.b[buf].ts_diagnostics_enable = true
        clear(buf)
        attach_buffer(buf)
        diagnose(buf)
    end
end

function M.disable_buf(buf)
    buf = buf or vim.api.nvim_get_current_buf()
    if vim.b[buf].ts_diagnostics_enable then
        vim.b[buf].ts_diagnostics_enable = false
        detach_buffer(buf)
    end
end

function M.toggle_buf(buf)
    buf = buf or vim.api.nvim_get_current_buf()
    if vim.b[buf].ts_diagnostics_enable then
        M.disable_buf(buf)
    else
        M.enable_buf(buf)
    end
end

local function walk(node, diags)
    if node:type() == "ERROR" or node:missing() then
        local parent = node:parent()
        if parent and parent:type() == "ERROR" and parent:range() == node:range() then
            -- skip this node
        else
            local sr, sc, er, ec = node:range()
            if er > sr then
                er = sr + 1
                ec = 0
            end
            if ec == sc then
                ec = sc + 1
            end
            local sev, msg, code
            if node:missing() then
                sev = vim.diagnostic.severity.ERROR
                msg = "missing" .. tostring(node:type())
                code = "ts-missing"
            else
                sev = vim.diagnostic.severity.ERROR
                msg = "syntax error"
                code = "ts-syntax"
            end
            diags[#diags+1] = { lnum = sr, col = sc, end_lnum = er, end_col = ec, severity = sev, message = msg, code=code, source="treesitter" }
        end
    end
    for child in node:iter_children() do
        walk(child)
    end
end

local function do_diagnose(buf)
    if not valid_buffer(buf) or not state[buf] then
        detach_buffer(buf)
        return
    end
    state[buf].running = true
    state[buf].tick = vim.api.nvim_buf_get_changedtick(buf)

    local ok, parser = pcall(vim.treesitter.get_parser, buf)
    if not ok or not parser then
        clear(buf)
        return
    end

    local diags = {}
    parser:parse(false, function(_, trees)
        local tree = trees and trees[1]
        if not tree then
            clear(buf)
            return
        end
        if not valid_buffer(buf) or not state[buf] then
            detach_buffer(buf)
            return
        end
        local root = tree:root()
        if root:has_error() then
            walk(root, diags)
        end
        if state[buf].pending or state[buf].tick ~= vim.api.nvim_buf_get_changedtick(buf) then
            state[buf].pending = false
            state[buf].running = false
            diagnose(buf)
            return
        else
            vim.diagnostic.set(ns, buf, diags)
        end
        state[buf].running = false
        cancel_timer(state[buf])
    end)
end

diagnose = function(buf)
    if not valid_buffer(buf) then
        detach_buffer(buf)
        return
    end
    if state[buf] and state[buf].tick == vim.api.nvim_buf_get_changedtick(buf) then
        return
    end
    if state[buf] and state[buf].running then
        state[buf].pending = true
        state[buf].tick = vim.api.nvim_buf_get_changedtick(buf)
        return
    end

    state[buf] = state[buf] or {}
    cancel_timer(state[buf])
    state[buf].timer = vim.uv.new_timer()
    state[buf].timer:start(config.debounce, 0, vim.schedule_wrap(function ()
        do_diagnose(buf)
    end))
end

function M.setup(opts)
    config = vim.tbl_deep_extend("force", DEFAULTS, opts or {})
    if config.enabled then
        M.enable()
    end
end

return M
