-- ── 类型声明（只给 lua_ls 看，运行时零开销） ──────────────────────────

---任务种类，同时也是 cfg.tasks 的键
---@alias TaskKind "run_test" | "run_regression"

---参数来源，按数组顺序依次尝试，全失败才弹窗
---@alias ResolverName "explicit" | "context" | "buffer" | "default"

---单个 test 的执行状态
---@alias TaskState "SUBMIT" | "WAIT_COMPILE" | "COMPILE_FAIL" | "WAIT_SIM" | "SIM" | "PASS" | "FAIL" | "UNKNOWN"

---回归任务的摘要状态，形如 "RUNNING: 3 PASS: 10 FAIL: 1"
---@alias TaskStateSummary string

---解析器与 build() 看到的只读上下文
---@class Context
---@field bufnr integer
---@field file string                # 当前 buffer 路径
---@field root string                # 项目根
---@field project? string
---@field module? string
---@field config table               # 模块配置（cfg）
---@field prev table<string, any>    # 已解析的参数

---模板里的单个参数声明
---@class ParamDecl
---@field name string
---@field type? "string" | "path" | "list" | "bool"
---@field multi? boolean             # 只有 list 有意义
---@field from? ResolverName[]
---@field options? fun(ctx: Context, prev: table<string, any>): string[]
---@field prompt? string             # 所有来源失败后的弹窗提示
---@field default? any
---@field validate? fun(v: any): boolean | string

---由 build() 声明、runner 落盘到任务目录的数据文件
---@class GeneratedFile
---@field path string                # 相对任务目录
---@field content string

---要执行什么（build() 的返回值），与“何时触发”无关
---@class TaskSpec
---@field kind TaskKind
---@field cwd string
---@field script? string             # 脚本文件，与 cmd 二选一
---@field cmd? string                # 简单命令行，与 script 二选一
---@field args? string[]             # 脚本位置参数
---@field env? string[]              # "KEY=VALUE" 或 "source ..."
---@field pre? string[]              # 前置命令
---@field files? GeneratedFile[]
---@field meta? table<string, any>

---一类任务的声明（内置 / 用户 / 项目）
---@class TaskTemplate
---@field name string
---@field desc? string
---@field source? "builtin" | "user" | "project"
---@field enabled? fun(ctx: Context): boolean
---@field params ParamDecl[]
---@field build fun(inputs: table<string, any>, ctx: Context): TaskSpec
---@field confirm? boolean           # 提交前是否预览渲染结果

---一次执行的历史记录
---@class RunEntry
---@field start_at string
---@field end_at? string
---@field state? TaskState | TaskStateSummary

---落盘的一条任务记录（手动提交与 cron 触发同构）
---@class TaskRecord
---@field id string
---@field kind TaskKind
---@field workdir string
---@field cmd string
---@field project string
---@field module string
---@field test? string
---@field tests? string[]
---@field list? string[]
---@field session string
---@field window string
---@field pane? string               # 只为“进去看现场”，不是存活依据
---@field run? RunEntry[]            # 提交时才创建

local M

local DEFAULTS = {
    root = "/proj/crane/wa",
    username = (vim.uv.os_get_passwd() or {}).username or vim.env.USER or vim.env.USERNAME,
}

local tasks = {
    run_test = {},
    run_regression = {}
}

local cfg = {
}

local function search_target(root, fn, opts)
    local targets = {}

    for name, _ in vim.fs.dir(root, opts or {}) do
        local p = vim.fs.joinpath(root, name)
        if fn(p) then
            targets[#targets+1] = p
        end
    end

    return targets
end

local function is_project(p)
    local stat = vim.uv.fs_stat(p)
    return stat and stat.type == "directory" and vim.uv.fs_stat(vim.fs.joinpath(p, ".SOS")) and true or false
end

local function is_module(p)
    local stat = vim.uv.fs_stat(p)
    local module = vim.fs.basename(p)
    return stat and stat.type == "directory" and vim.uv.fs_stat(vim.fs.joinpath(p, "cfg", module..".cfg")) and true or false
end

local function is_tc_file(p)
    return vim.uv.fs_stat(p) and vim.fs.ext(p) == "tc" and true or false
end

local function is_regression_list(p)
    return vim.uv.fs_stat(p) and vim.tbl_contains({"f", "lst"}, vim.fs.ext(p)) and true or false
end

local function select(prompt, items)
    local chosen = nil
    Snacks.picker.select(items, {
        prompt = prompt,
        format_item = vim.fs.basename
    }, function (item, _)
        chosen = item
    end)

    return chosen
end

local function pick(opts)
    local chosen = {}
    opts = vim.tbl_deep_extend("force", {
        format = "file",
        preview = "file",
        confirm = function (picker, _)
            chosen = picker:selected()
            picker:close()
        end
    }, opts)
    Snacks.picker.pick(opts)

    return chosen
end

local function parse_tests(file, emit)
    local test = {
        name = nil,
        file = file,
        lnr = 0,
    }
    local lnr = 0
    for line in io.lines(file) do
        lnr = lnr+1
        local s = vim.trim(line)
        if s ~= "" and s:sub(1,1) ~= "#" then
            if s == "endargs" then
                emit(test)
                test = {
                    name = nil,
                    file = file,
                    lnr = 0,
                }
            end
            if not test.name then
                test.name = line:match("^(%w+)%s*:%s*%w+$")
                test.name = test.name or line:match("^(%w+)%s*$")
                test.lnr = lnr
            end
        end
    end
end


local function select_tests(module)
    return pick({
        title = "Tests",
        finder = function (_, ctx)
            local files = search_target(vim.fs.joinpath(module, "testcases"), is_tc_file)
            return function(cb)
                for _, file in ipairs(files) do
                    if ctx.async:aborted() then
                        return
                    end
                    parse_tests(file, function (test)
                        cb({
                            text = test.name,
                            lable = test.name,
                            file = test.file,
                            pos = {test.lnr, 0}
                        })
                    end)
                    ctx.async:sleep(0)
                end
            end
        end
    })
end

local function select_regression_list(module)
    return pick({
        title = "Regression",
        items = search_target(vim.fs.joinpath(module, "regr"), is_regression_list)
    })
end

local function create_regression_list()
end

local function run_cmd(task)
    local pane
    if vim.system({"tmux", "has-session", "-t", "=", task.session}, { text = true}):wait().code == 0 then
        pane = vim.trim(vim.system({"tmux", "new-window", "-d", "-t", task.session, "-n", task.window}):wait().stdout)
    else
        pane = vim.trim(vim.system({"tmux", "new-session", "-d", "-s", task.session, "-n", task.window}):wait().stdout)
    end

    local msg = "Use cmd to check: tmux attach -t "..task.session..":"..task.window
    vim.notify("runsim: ".."Start cmd "..task.cmd.."on "..task.session..":"..task.window.."\n"..msg, vim.log.levels.INFO)
    if not task.run then
        task.run = {}
    end
    task.run[#task.run+1] = {
        start_at = os.date("!%Y%m%d_%H%M%S")
    }
    task.run[#task.run].state = "SUBMIT"
    vim.system({"tmux", "send-keys", "-t", pane, "-l", task.cmd}, function (out)
        task.run[#task.run].end_at = os.date("!%Y%m%d_%H%M%S")
        if out.code ~= 0 then
            vim.notify("runsim: "..task.cmd.." failed!\n"..msg, vim.log.levels.ERROR)
        else
            vim.notify("runsim: "..task.cmd.." completed!\n"..msg, vim.log.levels.INFO)
        end
    end)
end

function tasks.run_test.check(self)
    local compile_log = vim.fs.joinpath(self.workdir, "../compile", "compile.log")
    local compile_error_log = vim.fs.joinpath(self.workdir, "../compile", "cmp_error_message.log")
    local sim_log = vim.fs.joinpath(self.workdir, "sim_run.log")
    local pass_log = vim.fs.joinpath(self.workdir, "passed.log")
    local fail_log = vim.fs.joinpath(self.workdir, "failed.log")

    local state
    if not vim.uv.fs_stat(compile_log) then
        state = "WAIT_COMPILE"
    elseif vim.uv.fs_stat(compile_error_log) then
        state = "COMPILE_FAIL"
    elseif not vim.uv.fs_stat(sim_log) then
        state = "WAIT_SIM"
    elseif vim.uv.fs_stat(pass_log) then
        state = "PASS"
    elseif vim.uv.fs_stat(fail_log) then
        state = "FAIL"
    else
        state = "SIM"
    end

    self.run[#self.run].state = state
end

function tasks.run_regression.check(self)
    local workdir = vim.fs.joinpath(self.workdir, "latest_regr")
    local compile_log = vim.fs.joinpath(workdir, "compile", "compile.log")
    local compile_error_log = vim.fs.joinpath(workdir, "compile", "cmp_error_message.log")
    local this_regr_list = vim.fs.joinpath(workdir, "this_regression_list")

    if #self.list == 0 and vim.uv.fs_stat(this_regr_list) then
        for line in io.lines(this_regr_list) do
            self.list[#self.list+1] = vim.trim(line)
        end
    end

    local state
    if not vim.uv.fs_stat(compile_log) then
        state = "WAIT_COMPILE"
    elseif vim.uv.fs_stat(compile_error_log) then
        state = "COMPILE_FAIL"
    elseif #self.list > 0 then
        local pass = #search_target(workdir, function (p)
            return vim.fs.basename(p) == "passed.log"
        end, {depth = 1})

        local fail = #search_target(workdir, function (p)
            return vim.fs.basename(p) == "failed.log"
        end, {depth = 1})

        local running = #self.list - pass - fail

        state = "RUNNING: "..running.." PASS: "..pass.." FAIL: "..fail
    else
        state = "UNKNOWN"
    end

    self.run[#self.run].state = state
end
-- {
--     id         = "20261026-183012-a3f1",  -- 时间戳 + 4 位随机，可按名排序
--     kind       = "test",                  -- "test" | "regression"
--     workdir    = "/proj/.../runs/case_x",
--     cmd        = "cd ... && ./run.sh",    -- 实际执行的命令行（不含埋点）
--     project    = "...",
--     module     = "...",
--     tests      = { "foo_test" },          -- 连续数组
--     session    = "sim",
--     window     = "case_x",
--     pane       = "%12",                   -- 只为"进去看"，不是真相
--     started_at = 1793000000,
-- }
local seq
local function new_id()
    seq = seq+1
    return ("%s_%04d"):format(os.date("!%Y%m%d_%H%M%S"), seq)
end

local function build_task(kind, use_current_module)
    local project, module
    if use_current_module then
        if not is_project(vim.fs.joinpath(cfg.root, M.project or "")) then
            M.project = select("Project", search_target(cfg.root, is_project))
        end
        if not is_module(vim.fs.joinpath(cfg.root, M.project, "verification", M.module or "")) then
            M.module = select("Module", search_target(vim.fs.joinpath(cfg.root, M.project, "verification"), is_module))
        end
        project = M.project
        module = M.module
    else
        project = select("Project", search_target(cfg.root, is_project))
        module = select("Module", search_target(vim.fs.joinpath(cfg.root, M.project, "verification"), is_module))
    end

    return cfg.tasks[kind].build(project, module)
end

function tasks.run_test.build(project, module)
    local tests = select_tests(vim.fs.joinpath(cfg.root, project, "verification", module))
    if #tests == 0 then
        return nil
    elseif #tests > 1 then
        create_regression_list()
    else
        local id = new_id()
        local test = tests[1]
        local workdir = vim.fs.joinpath(cfg.output_disk, cfg.username, "runsim_nvim", project, module, id)
        local task = {
            id = id,
            kind = "run_test",
            workdir = workdir,
            cmd = "runsim -tb "..module.." -tc "..test.." -ws "..workdir,
            project = project,
            module = module,
            test = test,
            session = "runsim_nvim_"..project,
            window = test..id
        }
        return task
    end
end

local function run_task(task)
    vim.ui.input({
        prompt = task.kind.." args: ",
    }, function (value)
        task.cmd = task.cmd.." "..value
        run_cmd(task)
    end)
end

function M.run(use_current_module)
    local task = build_task(select("Tasks", vim.tbl_keys(cfg.tasks)), use_current_module)
    run_task(task)
end

function M.setup(opts)
    opts = vim.tbl_deep_extend("force", DEFAULTS, opts or {})
    opts.root = vim.fs.joinpath(opts.root, opts.username)
end

return M
