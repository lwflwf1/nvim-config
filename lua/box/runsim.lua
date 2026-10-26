local M

local DEFAULTS = {
    root = "/proj/crane/wa".. (vim.uv.os_get_passwd() or {}).username or vim.env.USER or vim.env.USERNAME
}

local opts = {
    commands = {
        run_test = {
        }
    }
}

local function search_target(root, fn, opts)
    local targets = {}

    for name, typ in vim.fs.dir(root, opts or {}) do
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
        prompt = "Project",
        format_item = vim.fs.basename
    }, function (item, idx)
        chosen = item
    end)

    return chosen
end

local function pick(opts)
    local chosen = {}
    opts = vim.tbl_deep_extend("force", {
        format = "file",
        preview = "file",
        confirm = function (picker, item)
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
            test.body[#test_body+1] = line
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

local function set_project(root)
    M.project = select("Project", search_target(root, is_project))
end

local function set_module(root)
    if M.project = nil then
        set_project()
    end

    M.module = select("Module", search_target(vim.fs.joinpath(root, M.project), is_module))
end

local function select_tests(module)
    return pick({
        title = "Tests",
        finder = function (opts, ctx)
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

local function do_run_regression()
    
end

local function do_run_test()
    
end

local function run_test()
    local tests = select_tests()
    if #tests > 1 then
        lst = create_regression_list(#tests)
        do_run_regression(lst)
    else
        do_run_test(tests[1])
    end
end

local function run_cmd(task)
    if vim.system({"tmux", "has-session", "-t", "=", task.session}, { text = true}):wait().code == 0 then
        local pane = vim.trim(vim.system({"tmux", "new-window", "-d", "-t", task.session, "-n", task.window}):wait().stdout)
    else
        local pane = vim.trim(vim.system({"tmux", "new-session", "-d", "-s", task.session, "-n", task.window}):wait().stdout)
    end

    local msg = "Use cmd to check: tmux attach -t "..task.session..":"..task.window
    vim.notify("runsim: ".."Start cmd "..task.cmd.."on "..task.session..":"..task.window.."\n"..msg, vim.log.levels.INFO)
    vim.system({"tmux", "send-keys", "-t", pane, "-l", task.cmd}, function (out)
        if out.code ~= 0 then
            vim.notify("runsim: "..task.cmd.." failed!\n"..msg, vim.log.levels.ERROR)
        else
            vim.notify("runsim: "..task.cmd.." completed!\n"..msg, vim.log.levels.INFO)
        end
    end)
    task.state = "SUBMIT"
end

local function check_run_test(task)
    local compile_log = vim.fs.joinpath(task.workdir, "../compile", "compile.log")
    local compile_error_log = vim.fs.joinpath(task.workdir, "../compile", "cmp_error_message.log")
    local sim_log = vim.fs.joinpath(task.workdir, "sim_run.log")
    local pass_log = vim.fs.joinpath(task.workdir, "passed.log")
    local fail_log = vim.fs.joinpath(task.workdir, "failed.log")

    if not vim.uv.fs_stat(compile_log) then
        task.state = "WAIT_COMPILE"
    elseif vim.uv.fs_stat(compile_error_log) then
        task.state = "COMPILE_FAIL"
    elseif not vim.uv.fs_stat(sim_log) then
        task.state = "WAIT_SIM"
    elseif vim.uv.fs_stat(pass_log) then
        task.state = "PASS"
    elseif vim.uv.fs_stat(fail_log) then
        task.state = "FAIL"
    else
        task.state = "SIM"
    end
end

local function check_run_regression(task)
    local compile_log = vim.fs.joinpath(task.workdir, "compile", "compile.log")
    local compile_error_log = vim.fs.joinpath(task.workdir, "compile", "cmp_error_message.log")
    local this_regr_list = vim.fs.joinpath(task.workdir, "this_regression_list")

    if #task.list == 0 and vim.uv.fs_stat(this_regr_list) then
        for line in io.lines(this_regr_list) do
            task.list[#task.list+1] = vim.trim(line)
        end
    end


    if not vim.uv.fs_stat(compile_log) then
        task.state = "WAIT_COMPILE"
    elseif vim.uv.fs_stat(compile_error_log) then
        task.state = "COMPILE_FAIL"
    elseif #task.list > 0 then
        local pass = #search_target(task.workdir, function (p)
            return vim.fs.basename(p) == "passed.log"
        end, {depth = 1})

        local fail = #search_target(task.workdir, function (p)
            return vim.fs.basename(p) == "failed.log"
        end, {depth = 1})

        local running = #task.list - pass - fail

        task.state = "RUNNING: "..running.." PASS: "..pass.." FAIL: "..fail
    else
        task.state = "UNKNOWN"
    end
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
    return ("%s-%04d"):format(os.date("!%Y%m%d-%H%M%S"), seq)
end

local function derive_project_module()
    local cwd = vim.fn.getcwd()
end

local function build_task(kind, run_current_module)
    if run_current_module then
        derive_project_module()
        if not M.project or is_project(vim.fs.joinpath(root, M.project)) then
            
        end
    end
    task = {
        id = new_id(),
        kind = kind,
        workdir = ,
        cmd = ,
        project = 
    }
    return task
end

local function run_task(task)
    
end

function M.run(run_current_module)
    local task = build_task(select("Tasks", vim.tbl_keys(opts.tasks)), run_current_module)
    run_task(task)
end

function M.setup(opts)
    opts = vim.tbl_deep_extend("force", DEFAULTS, opts or {})
end

return M
