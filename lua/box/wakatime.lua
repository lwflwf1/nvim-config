-- wakatime / wakapi operational commands.
--
-- Thin wrappers over the two scripts that move heartbeats across the air gap:
--   scripts/wakatime-export.sh  (RHEL6: dump the queue, pack, mail it out)
--   scripts/wakatime-fetch.py   (networked box: fetch, verify, upload)
--
-- Nothing here runs at startup. An earlier version of this module wrote
-- ~/.wakatime.cfg and linked the CLI on every nvim start; that moved into the
-- installers on purpose (AGENTS.md). Registering user commands is not that:
-- it only touches state when you actually invoke one.
--
-- `!` on any of these is fine for one-off inspection; the commands exist to keep
-- the argv (and the tool-availability errors) out of your fingers.
local M = {}

local function scripts_dir()
    return vim.fn.stdpath("config") .. "/scripts"
end

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
        vim.cmd("resize 18")
    else
        vim.api.nvim_set_current_buf(buf)
    end
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(body, "\n", { plain = true }))
    vim.bo[buf].modifiable = false
end

local function run(argv, title)
    local args = table.concat(argv, " ")
    show(title, "running: " .. args .. "\n")
    vim.system(argv, { text = true }, function(res)
        vim.schedule(function()
            show(title, table.concat({
                "$ " .. args,
                "exit: " .. tostring(res.code),
                "",
                res.stdout or "",
                res.stderr or "",
            }, "\n"))
        end)
    end)
end

local function split_args(s)
    if not s or s == "" then
        return {}
    end
    return vim.split(s, "%s+", { trimempty = true })
end

function M.export(args)
    local script = scripts_dir() .. "/wakatime-export.sh"
    if vim.fn.filereadable(script) ~= 1 then
        vim.notify("[wakatime] missing " .. script, vim.log.levels.ERROR)
        return
    end
    if vim.fn.executable("bash") ~= 1 then
        vim.notify("[wakatime] bash not found - :WakaExport runs on the RHEL6/Linux side",
            vim.log.levels.ERROR)
        return
    end
    local argv = { "bash", script }
    vim.list_extend(argv, split_args(args))
    run(argv, "export")
end

function M.sync(args)
    local script = scripts_dir() .. "/wakatime-fetch.py"
    if vim.fn.filereadable(script) ~= 1 then
        vim.notify("[wakatime] missing " .. script, vim.log.levels.ERROR)
        return
    end
    local py = nil
    for _, cand in ipairs({ "python3", "python" }) do
        if vim.fn.executable(cand) == 1 then
            py = cand
            break
        end
    end
    if not py then
        vim.notify("[wakatime] neither python3 nor python found - :WakaSync needs one",
            vim.log.levels.ERROR)
        return
    end
    local argv = { py, script }
    -- The credentials file is deliberately outside the repo; point at it instead
    -- of copying a password into a tree that has a GitHub remote.
    local cfg = vim.env.WAKATIME_IMAP_CONFIG
    if cfg and cfg ~= "" then
        vim.list_extend(argv, { "-c", cfg })
    end
    vim.list_extend(argv, { "sync" })
    vim.list_extend(argv, split_args(args))
    run(argv, "sync")
end

function M.setup()
    vim.api.nvim_create_user_command("WakaExport", function(a)
        M.export(a.args)
    end, { nargs = "*", desc = "Export the heartbeat queue and mail it (wakatime-export.sh)" })

    vim.api.nvim_create_user_command("WakaSync", function(a)
        M.sync(a.args)
    end, { nargs = "*", desc = "Fetch mailed heartbeat archives and upload them to wakapi" })
end

return M
