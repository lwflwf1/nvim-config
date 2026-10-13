-- wakatime / wakapi commands.
--
-- The air-gapped RHEL6 box cannot reach wakapi, so its heartbeats leave by mail
-- and come back over IMAP on a networked machine:
--
--   RHEL6   :WakaExport  -> bash scripts/wakatime-export.sh
--              wakatime-cli --print-offline-heartbeats -> ferry pack -> ferry email
--   here    :WakaSync    -> ferry recv -> ferry merge -> ferry unpack -> POST
--
-- The export half deliberately stays in the shell script, even though :WakaExport
-- could reimplement it here: that side must keep working when nvim cannot start
-- on the air-gapped box, so it has exactly one implementation and it does not
-- depend on this file. The sync half has no such constraint, so it lives here.
--
-- The IMAP half lives in ferry itself (`ferry recv`), next to the `email` command
-- that sends these archives -- ferry stays a generic transport tool and knows
-- nothing about wakapi, while everything wakapi-specific stays here.
--
-- Nothing runs at startup: these are user commands only. `!` is fine for one-off
-- inspection; the commands exist to keep the argv, the tool-availability errors
-- and the ledger bookkeeping out of your fingers.
local M = {}

local DEFAULT_FILTER = "Directory Archive: wakatime-"
local POST_PATH = "/users/current/heartbeats.bulk"

local function home()
    local h = vim.env.WAKATIME_HOME
    if h == nil or h == "" then
        h = vim.fn.expand("~")
    end
    return (h:gsub("\\", "/"))
end

local function scripts_dir()
    return (vim.fn.stdpath("config"):gsub("\\", "/")) .. "/scripts"
end

-- ---------------------------------------------------------------- output

local function show(title, body)
    local name = "wakatime://" .. title
    local buf = vim.fn.bufnr(name)
    if buf == -1 then
        buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_name(buf, name)
        vim.bo[buf].buftype = "nofile"
        vim.bo[buf].bufhidden = "hide"
        vim.bo[buf].filetype = "log"
        vim.api.nvim_open_win(buf, true, { split = "below", win = 0 })
        vim.cmd("resize 20")
    else
        vim.api.nvim_set_current_buf(buf)
    end
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(body, "\n", { plain = true }))
    vim.bo[buf].modifiable = false
end

local function err(msg)
    vim.notify("[wakatime] " .. msg, vim.log.levels.ERROR)
end

-- ---------------------------------------------------------------- misc

local function decode_json(text)
    local ok, value = pcall(vim.json.decode, text)
    return ok and value or nil
end

local function read_json(path)
    local fd = io.open(path, "r")
    if not fd then
        return nil
    end
    local text = fd:read("*a")
    fd:close()
    return decode_json(text)
end

local function write_json(path, value)
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    local fd = io.open(path, "w")
    if not fd then
        return false
    end
    fd:write(vim.json.encode(value) .. "\n")
    fd:close()
    return true
end

local function split_args(s)
    if not s or s == "" then
        return {}
    end
    return vim.split(s, "%s+", { trimempty = true })
end

-- Run a command and hand (code, stdout, stderr) back on the main loop.
local function sh(argv, cwd, cb)
    vim.system(argv, { text = true, cwd = cwd }, function(res)
        vim.schedule(function()
            cb(res.code or -1, res.stdout or "", res.stderr or "")
        end)
    end)
end

-- Sequential async steps: each gets a `next` callback; failures still advance so
-- one broken archive cannot abort the rest of the run.
local function chain(steps, done)
    local i = 0
    local function advance()
        i = i + 1
        local step = steps[i]
        if not step then
            return done and done()
        end
        step(advance)
    end
    advance()
end

-- ---------------------------------------------------------------- config

local function find_cfg()
    local explicit = vim.env.WAKATIME_IMAP_CONFIG
    if explicit and explicit ~= "" then
        return explicit
    end
    for _, cand in ipairs({ vim.fn.getcwd() .. "/imap.json", scripts_dir() .. "/imap.json" }) do
        if vim.fn.filereadable(cand) == 1 then
            return cand
        end
    end
    return nil
end

local function find_ferry(cfg)
    local function as_py(p)
        if p:lower():sub(-4) == ".cmd" then
            p = p:sub(1, -5) .. ".py"
        end
        return vim.fn.filereadable(p) == 1 and p or nil
    end
    if cfg.ferry and cfg.ferry ~= "" then
        local p = as_py(cfg.ferry)
        if not p then
            err('config "ferry" does not point at a ferry.py: ' .. tostring(cfg.ferry))
        end
        return p
    end
    for _, name in ipairs({ "ferry.py", "ferry" }) do
        local w = vim.fn.exepath(name)
        if w ~= "" then
            local p = as_py(w)
            if p then
                return p
            end
        end
    end
    err('ferry.py not found; set "ferry" in imap.json to its full path')
    return nil
end

local function find_python()
    for _, cand in ipairs({ "python3", "python" }) do
        if vim.fn.executable(cand) == 1 then
            return cand
        end
    end
    err("neither python3 nor python found - ferry needs one")
    return nil
end

-- api_url + api_key from the CLI's own config: wakatime-cli binds no env var for
-- api_url, so ~/.wakatime.cfg is the only place it can live.
local function wakatime_credentials()
    local path = home() .. "/.wakatime.cfg"
    if vim.fn.filereadable(path) ~= 1 then
        return nil, nil, "missing " .. path
    end
    local section, url, key = nil, nil, nil
    for _, line in ipairs(vim.fn.readfile(path)) do
        local s = line:match("^%s*(.-)%s*$")
        local sec = s:match("^%[(.-)%]$")
        if sec then
            section = sec
        elseif section == "settings" then
            local k, v = s:match("^([%w_]+)%s*=%s*(.-)%s*$")
            if k == "api_url" then
                url = v
            elseif k == "api_key" then
                key = v
            end
        end
    end
    if not url or url == "" then
        return nil, nil, "api_url is not set in " .. path
    end
    if not key or key == "" then
        return nil, nil, "api_key is not set in " .. path .. " (run :WakaTimeApiKey)"
    end
    if url:find("127%.0%.0%.1:1") then
        return nil, nil, "api_url is the air-gapped placeholder (" .. url .. "); this machine cannot upload"
    end
    return (url:gsub("/+$", "")), key
end

-- ---------------------------------------------------------------- staging

-- Group the downloaded attachments by archive. ferry names split parts
-- "<archive>.partNNN.<ext>", so ".partNNN" identifies them; anything else is a
-- single-part archive (ferry skips splitting when the zip fits in 1 MiB).
local function group_archives(dir)
    local groups = {}
    local function add(key, idx, is_part)
        local g = groups[key]
        if not g then
            g = { have = {}, is_part = is_part }
            groups[key] = g
        end
        g.have[idx] = true
    end
    for _, full in ipairs(vim.fn.glob(dir .. "/*", false, true)) do
        if vim.fn.filereadable(full) == 1 then
            local name = vim.fn.fnamemodify(full, ":t")
            local base, idx = name:match("^(.-)%.part(%d+)%.[^.]*$")
            if base then
                add(base, tonumber(idx), true)
            else
                add(name, 1, false)
            end
        end
    end
    return groups
end

local function count_have(g)
    local n = 0
    for _ in pairs(g.have) do
        n = n + 1
    end
    return n
end

-- ---------------------------------------------------------------- wakapi

local function post_heartbeats(api_url, key, path, cb)
    local argv = {
        "curl", "-sS", "-X", "POST",
        "-H", "Authorization: Basic " .. vim.base64.encode(key),
        "-H", "Content-Type: application/json",
        "-H", "Accept: application/json",
        "--data-binary", "@" .. path,
        api_url .. POST_PATH,
    }
    sh(argv, nil, function(code, out, e)
        local parsed = decode_json(out)
        if type(parsed) ~= "table" or type(parsed.responses) ~= "table" then
            return cb(nil, ("HTTP-layer failure (curl %d): %s"):format(code, (out .. e):sub(1, 200)))
        end
        local tally, accepted, rejected = {}, 0, 0
        for _, item in ipairs(parsed.responses) do
            if type(item) == "table" and #item >= 2 then
                local status = item[#item]
                tally[status] = (tally[status] or 0) + 1
                if status == 201 then
                    accepted = accepted + 1
                elseif status == 400 then
                    rejected = rejected + 1
                end
            end
        end
        cb({ accepted = accepted, rejected = rejected, tally = tally })
    end)
end

-- ---------------------------------------------------------------- commands

function M.export(args)
    local script = scripts_dir() .. "/wakatime-export.sh"
    if vim.fn.filereadable(script) ~= 1 then
        return err("missing " .. script)
    end
    if vim.fn.executable("bash") ~= 1 then
        return err("bash not found - :WakaExport runs on the RHEL6/Linux side")
    end
    local argv = { "bash", script }
    vim.list_extend(argv, split_args(args))
    local cmd = table.concat(argv, " ")
    show("export", "running: " .. cmd .. "\n")
    sh(argv, nil, function(code, out, e)
        -- The script's warn() goes to stderr, and its two most important
        -- messages ("mailing failed, artifacts kept" / "queue grew, keeping it")
        -- are warnings -- so stderr first, or they read as an afterthought.
        show("export", table.concat({
            "$ " .. cmd,
            "exit: " .. code,
            "",
            e,
            out,
        }, "\n"))
        if code ~= 0 then
            err(cmd .. " exited " .. code .. " - see the wakatime://export buffer")
        end
    end)
end

function M.sync(args)
    local opt = { force = false, keep_mails = false, only = nil }
    local argv = split_args(args)
    for i = 1, #argv do
        local a = argv[i]
        if a == "--force" then
            opt.force = true
        elseif a == "--keep-mails" then
            opt.keep_mails = true
        elseif (a == "-a" or a == "--archive") and argv[i + 1] then
            opt.only = argv[i + 1]
        end
    end

    local cfg_path = find_cfg()
    if not cfg_path then
        return err("no imap.json found (WAKATIME_IMAP_CONFIG, cwd, or " .. scripts_dir() .. ")")
    end
    local cfg = read_json(cfg_path)
    if type(cfg) ~= "table" then
        return err("imap.json is not valid JSON: " .. cfg_path)
    end

    local ferry = find_ferry(cfg)
    if not ferry then
        return
    end
    local py = find_python()
    if not py then
        return
    end
    if vim.fn.executable("curl") ~= 1 then
        return err("curl not found - :WakaSync needs it to POST to wakapi")
    end

    local api_url, key, why = wakatime_credentials()
    if not api_url then
        return err(why)
    end

    local filter = cfg.subject_filter or DEFAULT_FILTER
    local staging = (cfg.staging and vim.fn.expand(cfg.staging))
        or (home() .. "/wakatime-ferry/incoming")
    local state_path = (cfg.state_file and vim.fn.expand(cfg.state_file))
        or (home() .. "/wakatime-ferry/state.json")
    local work = staging .. "/.work"

    vim.fn.mkdir(staging, "p")
    vim.fn.mkdir(work, "p")
    local ledger = read_json(state_path) or {}
    ledger.uploaded = ledger.uploaded or {}

    local log = {}
    local function say(s)
        log[#log + 1] = s
        show("sync", table.concat(log, "\n"))
    end

    say("api_url : " .. api_url)
    say("config  : " .. cfg_path)
    say("staging : " .. staging)
    say("")

    local recv_argv = { py, ferry, "recv", "-c", cfg_path, "-o", staging, "-s", filter }
    if not opt.keep_mails then
        recv_argv[#recv_argv + 1] = "--mark-seen"
    end

    say("$ " .. table.concat(recv_argv, " "))
    sh(recv_argv, nil, function(code, out, e)
        -- stderr first: it carries ferry's "connecting/connected" diagnostics,
        -- which read wrong after the result report.
        if e ~= "" then
            say(e)
        end
        say(out)
        if code ~= 0 then
            say(("recv exited %d - stopping (nothing was uploaded)"):format(code))
            return
        end
        say("")

        local groups = group_archives(staging)
        local names = vim.tbl_keys(groups)
        table.sort(names)
        if #names == 0 then
            say("no archives in the staging dir")
            return
        end

        local todo = {}
        for _, name in ipairs(names) do
            if opt.only and name ~= opt.only then
                -- still reported below, just not processed
            elseif ledger.uploaded[name] and not opt.force then
                say(("skip %s (uploaded %s)"):format(name, ledger.uploaded[name].at or "?"))
            else
                todo[#todo + 1] = name
            end
        end
        if #todo == 0 then
            say("nothing new to upload" .. (opt.force and "" or " (--force re-uploads)"))
            return
        end

        local steps = {}
        local uploaded, failed = {}, {}
        for _, name in ipairs(todo) do
            steps[#steps + 1] = function(next_step)
                local g = groups[name]
                say(("== %s ==="):format(name))
                say(("   %d part file(s) present"):format(count_have(g)))

                local merged = work .. "/" .. name
                local extracted = work .. "/" .. name .. ".d"

                local function unpack(archive)
                    vim.fn.delete(extracted, "rf")
                    sh({ py, ferry, "unpack", "-i", archive, "-o", extracted }, nil,
                        function(uc, uo, ue)
                            if uc ~= 0 then
                                say("   [X] unpack rejected the archive (incomplete or"
                                    .. " corrupted in transit); keeping the parts")
                                say("       " .. ((ue ~= "" and ue or uo):gsub("\n", "\n       ")))
                                say("       if this repeats, the mail path is mangling the"
                                    .. " attachment - switch the RHEL6 side to ferry's"
                                    .. " -f text")
                                failed[#failed + 1] = name
                                return next_step()
                            end
                            local jsons = vim.fn.glob(extracted .. "/**/*.json", false, true)
                            if #jsons == 0 then
                                say("   [!] unpack produced no .json")
                                failed[#failed + 1] = name
                                return next_step()
                            end
                            say("   integrity OK -> " .. vim.fn.fnamemodify(jsons[1], ":t"))
                            post_heartbeats(api_url, key, jsons[1], function(res, perr)
                                if perr then
                                    say("   [!] " .. perr)
                                    failed[#failed + 1] = name
                                    return next_step()
                                end
                                say(("   POST accepted=%d rejected=%d"):format(
                                    res.accepted, res.rejected))
                                if res.rejected > 0 then
                                    say("   [!] rejected heartbeats are usually older than"
                                        .. " heartbeat_max_age (180d) or malformed")
                                    failed[#failed + 1] = name
                                    return next_step()
                                end
                                ledger.uploaded[name] = {
                                    at = os.date("%Y-%m-%dT%H:%M:%S"),
                                    heartbeats = res.accepted,
                                }
                                write_json(state_path, ledger)
                                uploaded[#uploaded + 1] = name
                                say("   recorded in the ledger")
                                next_step()
                            end)
                        end)
                end

                if g.is_part then
                    local parts = vim.fn.glob(staging .. "/" .. name .. ".part[0-9][0-9][0-9]*", false, true)
                    table.sort(parts)
                    if #parts == 0 then
                        say("   [!] no part files found for " .. name)
                        failed[#failed + 1] = name
                        return next_step()
                    end
                    say("$ " .. py .. " " .. ferry .. " merge -i " .. parts[1])
                    sh({ py, ferry, "merge", "-i", parts[1], "-o", merged }, nil,
                        function(mc, mo, me)
                            if mc ~= 0 then
                                say("   [!] merge failed (a part is still missing?): "
                                    .. ((me ~= "" and me or mo):gsub("\n", " "):sub(1, 160)))
                                failed[#failed + 1] = name
                                return next_step()
                            end
                            unpack(merged)
                        end)
                else
                    unpack(staging .. "/" .. name)
                end
            end
        end

        steps[#steps + 1] = function(next_step)
            say("")
            if #uploaded > 0 then
                say("uploaded: " .. table.concat(uploaded, ", "))
            end
            if #failed > 0 then
                say("not uploaded (left in the staging dir, re-runs are safe): "
                    .. table.concat(failed, ", "))
            end
            next_step()
        end

        chain(steps)
    end)
end

function M.setup()
    vim.api.nvim_create_user_command("WakaExport", function(a)
        M.export(a.args)
    end, { nargs = "*", desc = "Export the heartbeat queue and mail it (runs scripts/wakatime-export.sh)" })

    vim.api.nvim_create_user_command("WakaSync", function(a)
        M.sync(a.args)
    end, { nargs = "*", complete = function()
        return { "--force", "--keep-mails", "-a" }
    end, desc = "Fetch mailed heartbeat archives and upload them to wakapi" })
end

return M
