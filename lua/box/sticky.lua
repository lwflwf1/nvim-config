local M = {}

local DEFAULTS = {
    mappings = {
        g = {
            keys = {
                r,
                h,
                a,
                {b, function ()

                end},
            },
        },
    }
}

local timeout

local function feedkeys(s, mode)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(s, true, true, true), mode or "m", false)
end

local function on_enter(key)
    timeout = vim.o.timeout
    vim.o.timeout = false
    M.prefix = key
end

local function on_exit(key)
    vim.o.timeout = timeout
    M.prefix = nil
end

local function set_keymaps(plug, keys)
    for _, key in ipairs(keys) do
        if type(key) == "table" then
            vim.keymap.set("n", plug..key[1], function ()
                if type(key[2]) == "function" then
                    key[2]()
                elseif type(key[2]) == "string" then
                    feedkeys(key[2])
                else
                    vim.notify("sticky: rhs of a map"..key[1].." must be a function or string!", vim.log.levels.ERROR)
                end
                feedkeys(plug)
            end)
        elseif type(key) == "string" then
            vim.keymap.set("n", plug..key, function ()
                feedkeys(prefix..key)
                feedkeys(plug)
            end)
        else
            vim.notify("sticky: item of mappings must be table or string", vim.log.levels.ERROR)
        end
    end
end

function M.setup(opts)
    opts = vim.tbl_deep_extend("force", DEFAULTS, opts or {})
    for prefix, v in pairs(opts) do
        local plug = "<Plug>(sticky_"..prefix..")"
        vim.keymap.set("n", prefix, function ()
            set_keymaps(prefix, v.keys)
            on_enter()
            feedkeys(plug)
        end)

        vim.keymap.set("n", plug, function ()
            on_exit()
        end)
    end
end









return M
