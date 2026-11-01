--- task definition
---@class TaskDefinition
---@field name string
---@field desc? string
---@field params ParamDefinition[]
---@field build fun(self: TaskDefinition, resolved: table, ctx: table): TaskSpec
---@field resolve_context fun(): table
---@field check fun(): string
---@field confirm? boolean

---parameter definition
---@class ParamDefinition
---@field name string
---@field desc? string
---@field from string[] | fun(): any # default: explicit, context, prompt
---@field choices string[] | fun(ctx: table, resolved: table): string[]
---@field finder fun(ctx: table, resolved: table): fun(opts, ctx)
---@field required? boolean # default: true
---@field default? any
---@field validate? fun(v: any): boolean | string

---@class TaskSpec
---@field name string
---@field kind string
---@field cwd string
---@field workdir string
---@field script? string
---@field cmds? string[]
---@field args? string[]
---@field env? string[]              # "KEY=VALUE" 或 "source ..."
---@field session string
---@field window string
---@field meta? table<string, any>

---@class TaskRecord
---@field spec TaskSpec
---@field id string
---@field start_at string
---@field end_at string
---@field session string
---@field window string
---@field pane string               # 只为“进去看现场”，不是存活依据

local select = vim.async.wrap(3, function (prompt, items, cb)
    Snacks.picker.select(items, {
        prompt = prompt,
        format_item = vim.fs.basename
    }, function (item, _)
            cb(item)
        end
    )
end)

local pick = vim.async.wrap(2, function (opts, cb)
    local done = false
    opts = vim.tbl_deep_extend("force", {
        format = "file",
        preview = "file",
        confirm = function (picker, _)
            local selected = picker:selected({ fallback=true })
            done = true
            cb(#selected > 0 and selected or nil)
            picker:close()
        end,
        on_close = function ()
            if not done then
                done = true
                cb(nil)
            end
        end
    }, opts)
    Snacks.picker.pick(opts)
end)

local input = vim.async.wrap(2, function (opts, cb)
    vim.ui.input(opts, function (v)
        cb(v ~= nil and v ~= "" and v or nil)
    end)
end)

local resolver = {
    explicit = function (env)
        return env.args[env.pd.name]
    end,

    context = function (env)
        return env.ctx[env.pd.name]
    end,

    prompt = function (env)
        local pd, ctx, resolved = env.pd, env.ctx, env.resolved
        if pd.choices then
            local items = type(pd.choices) == "function" and pd.choices(ctx, resolved) or pd.choices
            return select(pd.name, items)
        end

        if pd.finder then
            return pick({
                title = pd.name,
                finder = pd.finder(ctx, resolved)
            })
        end

        return input({
            prompt = pd.name,
        })
    end,
}

local function resolve_parameters(params, args, ctx)
    local resolved = {}
    for _, pd in ipairs(params) do
        pd.from = pd.from or {"explicit", "context", "prompt"}
        for _, f in ipairs(pd.from) do
            local env = {
                args = args,
                pd = pd,
                resolved = resolved,
                ctx = ctx,
            }
            local v
            if not resolver[f] then
                vim.notify("Task: resolver "..f.." is not defined", vim.log.levels.ERROR)
            else
                v = resolver[f](env)
                if v ~= nil then
                    resolved[pd.name] = v
                    break
                end
            end
        end
        resolved[pd.name] = resolved[pd.name] or pd.default
        local required = pd.required or true
        if resolved[pd.name] == nil and required then
            error("Task: parameter "..pd.name.." is not specified")
        end
    end

    return resolved
end

---@param task TaskDefinition
---@param args table
---@return TaskSpec
local function build_task(task, args)
    local ctx = task.resolve_context()
    local resolved = resolve_parameters(task.params, args, ctx)
    spec = task.build(task, resolved, ctx)
    spec.meta = {
        args = args,
        resolved = resolved,
    }
    return spec
end

---@param spec TaskSpec
---@return string
local function build_cmd(spec)
    
end

---@param spec TaskSpec
function M.run_task(spec)
    local record

    record = {
        spec = spec,
        id = os.date("%Y%m%d%H%M%S"),
        start_at = os.date("%Y-%m-%d %H:%M:%S")
        session = spec.session,
        window = spec.window,
    }

    local pane

    if vim.system({"tmux", "has-session", "-t", "=", record.session}, { text = true}):wait().code == 0 then
        pane = vim.trim(vim.system({"tmux", "new-window", "-d", "-t", record.session, "-n", record.window}):wait().stdout)
    else
        pane = vim.trim(vim.system({"tmux", "new-session", "-d", "-s", record.session, "-n", record.window}):wait().stdout)
    end

    record.pane = pane

    local msg = "Use cmd to check: tmux attach -t "..spec.session..":"..spec.window
    vim.notify("Task: ".."Start task "..spec.name.." on "..spec.session..":"..spec.window.."\n"..msg, vim.log.levels.INFO)
    store_record(record)
    local cmd = build_cmd(spec)
    vim.system({"tmux", "send-keys", "-t", pane, "-l", cmd}, function (out)
        update_record(record)
        if out.code ~= 0 then
            vim.notify("Task: "..spec.name.." failed!\n"..msg, vim.log.levels.ERROR)
        else
            vim.notify("Task: "..spec.name.." completed!\n"..msg, vim.log.levels.INFO)
        end
    end)
end

return M
