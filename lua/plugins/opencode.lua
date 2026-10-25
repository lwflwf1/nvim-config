-- Give every Neovim instance its own OpenCode server on a private port: a lazily
-- allocated free port is threaded into both the URL and the started terminal.
--
-- The URL is load-bearing. Without it, discovery adopts ANY local
-- `opencode --port` whose cwd overlaps, so a second nvim on the same project
-- silently talks to the first one's opencode (`configured()` is checked before
-- `locally()`). Trade-off: a manually started `opencode` is no longer adopted.
local port
local function server_port()
    if not port then
        local tcp = assert(vim.uv.new_tcp())
        tcp:bind("127.0.0.1", 0)
        port = tcp:getsockname().port
        tcp:close()
    end
    return port
end

-- Shared so the toggle key finds the same terminal `server.start` opened (snacks
-- dedups terminals by command string).
local function server_cmd()
    return ("opencode --port %d"):format(server_port())
end

return {
    {
        "nickjvandyke/opencode.nvim",
        -- Pin the plugin to the 1.x tags, which are the OpenCode v1 line -- the line
        -- the installed CLI (1.19.0) speaks.
        --   * "*" does NOT mean "latest tag" here: it resolved to main's tip,
        --     which is where v2 support is being built.
        --   * "~1" tracks the latest 1.x tag and can never select a v2 tag.
        -- Do NOT use vim.version.range("*"): it returns a table and lazy's
        -- version field wants a string (semver.lua:138 does spec:find).
        version = "~1",
        enabled = not vim.g.is_rhel6,
        keys = {
            {
                "<leader>ao",
                function() require("opencode").ask("@this: ") end,
                desc = "OpenCode ask",
                mode = { "n", "x" },
            },
            {
                "<leader>aO",
                function() require("opencode").select() end,
                desc = "OpenCode select",
                mode = { "n", "x" },
            },
            {
                "<leader>ag",
                function() return require("opencode").operator("@this") end,
                desc = "OpenCode send range",
                mode = { "n", "x" },
                expr = true,
            },
            {
                "<leader>aG",
                function() return require("opencode").operator("@this") .. "_" end,
                desc = "OpenCode send line",
                mode = { "n" },
                expr = true,
            },
            {
                "<leader>aT",
                function() require("snacks.terminal").toggle(server_cmd()) end,
                desc = "Toggle OpenCode terminal",
                mode = { "n", "t" },
            },
        },
        -- ask() and select() auto-detect snacks.input / snacks.picker (both enabled
        -- in plugins/snacks.lua), so only the server defaults are replaced: a
        -- pinned per-instance URL (see top of file) and a snacks terminal
        -- instead of a bare vsplit.
        --
        -- `init`, not `opts`: this plugin has no setup(), and lazy silently
        -- drops `opts` without one. It reads vim.g.opencode_opts instead, which
        -- its config.lua consumes on first require.
        init = function()
            vim.g.opencode_opts = {
                server = {
                    url = function(resolve)
                        resolve(("http://127.0.0.1:%d"):format(server_port()))
                    end,
                    start = function()
                        require("snacks.terminal").open(server_cmd(), {
                            win = { position = "right", enter = false },
                        })
                    end,
                },
            }
        end,
    },
}
