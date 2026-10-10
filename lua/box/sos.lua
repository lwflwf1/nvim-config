-- SOS source control + work-generator commands (RHEL6 tooling). Consolidated
-- from core/autocmds.lua (the Sco/... commands and Tgen/Rm/Fp) and
-- core/keymaps.lua (the <leader>s* mappings), so the generic core files stay
-- generic. setup() registers the commands and the mappings.
local M = {}

local function sos_file()
    return vim.fn.expand("%")
end

--- Run the SOS CLI (/tools/SOS/gold/bin/soscmd) asynchronously and report
--- success/failure through the notifier.
local function sos_notify(op, args, reload, stdin)
    local opts = { text = true }
    if stdin then
        opts.stdin = stdin
    end
    vim.system(args, opts, function(result)
        local out = vim.trim((result.stdout or "") .. "\n" .. (result.stderr or ""))
        out = out:gsub("\n+$", "")
        if result.code == 0 then
            local msg = op .. " succeeded"
            if out ~= "" then
                msg = msg .. ":\n" .. out
            end
            vim.notify(msg, vim.log.levels.INFO, { title = "SOS " .. op })
            if reload then
                -- co/discard/update change the file on disk (e.g. read-only -> writable
                -- after co, or content reverted after discard/update), so re-read the
                -- current buffer to pick up the new permission/content.
                vim.schedule(function()
                    vim.cmd("edit!")
                end)
            end
        else
            local msg = (out ~= "" and out or op .. " failed") .. " (exit " .. result.code .. ")"
            vim.notify(msg, vim.log.levels.ERROR, { title = "SOS " .. op })
        end
    end)
end

function M.setup()
    vim.api.nvim_create_user_command("Sco", function()
        sos_notify("co", { "/tools/SOS/gold/bin/soscmd", "co", sos_file() }, true)
    end, {})

    vim.api.nvim_create_user_command("Scon", function()
        sos_notify("co -Nlock", { "/tools/SOS/gold/bin/soscmd", "co", "-Nlock", sos_file() }, true)
    end, {})

    vim.api.nvim_create_user_command("Sci", function()
        local summary = vim.fn.input("Change summary: ")
        if summary == "" then
            return
        end
        sos_notify("ci", { "/tools/SOS/gold/bin/soscmd", "ci", sos_file() }, true, summary .. "\n")
    end, {})

    vim.api.nvim_create_user_command("Scim", function(opts)
        if opts.args == "" then
            return
        end
        sos_notify("ci", { "/tools/SOS/gold/bin/soscmd", "ci", sos_file() }, true, opts.args .. "\n")
    end, { nargs = 1 })

    vim.api.nvim_create_user_command("Sd", function()
        sos_notify("discard", { "/tools/SOS/gold/bin/soscmd", "discard", sos_file() }, true)
    end, {})

    vim.api.nvim_create_user_command("Sdf", function()
        sos_notify("discard -F", { "/tools/SOS/gold/bin/soscmd", "discard", "-F", sos_file() }, true)
    end, {})

    vim.api.nvim_create_user_command("Sup", function()
        sos_notify("update", { "/tools/SOS/gold/bin/soscmd", "update" }, true)
    end, {})

    vim.api.nvim_create_user_command("Scr", function()
        sos_notify("create", { "/tools/SOS/gold/bin/soscmd", "create", sos_file() })
    end, {})

    -- Work generators
    vim.api.nvim_create_user_command("Tgen", function(opts)
        vim.cmd("exec '!tempgen.py -f % -t " .. opts.args .. "'")
    end, { nargs = 1 })
    vim.api.nvim_create_user_command("Rm", "exec '!run_mako.py'", {})
    vim.api.nvim_create_user_command("Fp", "exec '!gen_func_prototype.py -s % -p %:h'", {})

    -- SOS source control shortcuts
    -- map("n", "<leader>so", ":Sco<CR>", vim.tbl_extend("force", opts, { desc = "SOS checkout" }))
    local map = function(lhs, rhs, desc)
        vim.keymap.set("n", lhs, rhs, { noremap = true, silent = true, desc = desc })
    end
    map("<leader>so", ":Scon<CR>", "SOS checkout (Nlock)")
    map("<leader>si", ":Sci<CR>", "SOS checkin")
    map("<leader>sI", function()
        local msg = vim.fn.input("Change summary: ")
        if msg ~= "" then
            vim.cmd("Scim " .. msg)
        end
    end, "SOS checkin with message")
    map("<leader>sd", ":Sd<CR>", "SOS discard")
    map("<leader>sD", ":Sdf<CR>", "SOS discard -F")
    map("<leader>su", ":Sup<CR>", "SOS update")
    map("<leader>sr", ":Scr<CR>", "SOS create")
end

return M
