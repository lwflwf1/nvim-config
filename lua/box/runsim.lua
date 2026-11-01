local M

local task = require("box.task")

local DEFAULTS = {
    root = "/proj/crane/wa",
    username = (vim.uv.os_get_passwd() or {}).username or vim.env.USER or vim.env.USERNAME,
}

local cfg = {}

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

local function search_target(root, filter, opts)
    local targets = {}

    for name, _ in vim.fs.dir(root, opts or {}) do
        local p = vim.fs.joinpath(root, name)
        if filter == nil or filter(p) then
            targets[#targets+1] = p
        end
    end

    return targets
end

local function resolve_context()
    local ctx = {}
    local cwd = vim.uv.cwd()
    ctx.project, ctx.module = cwd:match("^"..vim.fs.normalize(cfg.root).."/(%w+)/verification/(%w+)")
    if ctx.project ~= nil then
        ctx.project_path = vim.fs.joinpath(cfg.root, ctx.project)
    end
    if ctx.module ~= nil then
        ctx.module_path = vim.fs.joinpath(ctx.project_path, "verification", ctx.module)
    end
    return ctx
end

---@type TaskDefinition[]
local tasks = {
    run_test = {
        name = "run_test",
        desc = "run single test",
        params = {
            { name = "project", choices = function ()
                return search_target(cfg.root, is_project)
            end},
            { name = "module", choices = function (_, resolved)
                return search_target(vim.fs.joinpath(ctx.root, resolved.project, "verification"), is_module)
            end},
            { name = "test", finder = function (ctx, resolved)
                local files = search_target(vim.fs.joinpath(ctx.root, resolved.project, "verification", resolved.module, "testcases"), is_tc_file)
                return function (_, sctx)
                    return function(cb)
                        for _, file in ipairs(files) do
                            if sctx.async:aborted() then
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
                            sctx.async:sleep(0)
                        end
                    end
                end
            end },
            { name = "env", choices = function ()
                return search_target(vi.fs.joinpath(ctx.root, "bin"))
            end }
            { name = "other", required=false },
        },
        confirm = true,
        resolve_context = resolve_context,
    },
}

function tasks.run_test.build(self, resolved, ctx)
    local id = new_id()
    local workdir = vim.fs.joinpath(cfg.output_disk, cfg.username, "runsim_nvim", ctx.project, ctx.module, id)
    local task = {
        id = id,
        kind = self.name,
        cwd = ctx.project_path
        workdir = workdir,
        env = {resolved.env}
        cmds = {"runsim -tb "..resolved.module.." -tc "..resolved.test.." -ws "..workdir},
        project = resolved.project,
        module = resolved.module,
        session = "runsim_nvim_"..project,
        window = test..id
    }
    return task
end

local function select_regression_list(module)
    return pick({
        title = "Regression",
        items = search_target(vim.fs.joinpath(module, "regr"), is_regression_list)
    })
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

function M.run(use_current_module)
end

function M.setup(opts)
    opts = vim.tbl_deep_extend("force", DEFAULTS, opts or {})
    opts.root = vim.fs.joinpath(opts.root, opts.username)
end

return M
