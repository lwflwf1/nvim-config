local data = vim.fn.stdpath('data')

local promise_async_impl
local async_nvim_impl

local function get_promise_async()
    if not promise_async_impl then
        promise_async_impl = dofile(data .. '/lazy/promise-async/lua/async.lua')
    end
    return promise_async_impl
end

local function get_async_nvim()
    if not async_nvim_impl then
        async_nvim_impl = dofile(data .. '/lazy/async.nvim/lua/async.lua')
    end
    return async_nvim_impl
end

return setmetatable({}, {
    __index = function(_, key)
        local v = get_promise_async()[key]
        if v ~= nil then return v end
        return get_async_nvim()[key]
    end,
    __call = function(_, ...)
        return get_promise_async()(...)
    end,
})
