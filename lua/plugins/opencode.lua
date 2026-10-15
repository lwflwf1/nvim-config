-- Shared so the toggle key finds the same terminal `server.start` opened.
local server_cmd = "opencode --port"

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
                "<leader>as",
                function() require("snacks.terminal").toggle(server_cmd) end,
                desc = "Toggle OpenCode terminal",
                mode = { "n", "t" },
            },
        },
        -- ask() and select() auto-detect snacks.input / snacks.picker (both enabled
        -- in plugins/snacks.lua), so the only default worth replacing is the
        -- server: a snacks terminal instead of a bare vsplit.
        --
        -- `init`, not `opts`: this plugin has no setup(), and lazy silently
        -- drops `opts` without one. It reads vim.g.opencode_opts instead, which
        -- its config.lua consumes on first require.
        init = function()
            vim.g.opencode_opts = {
                server = {
                    start = function()
                        require("snacks.terminal").open(server_cmd, {
                            win = { position = "right", enter = false },
                        })
                    end,
                },
            }
        end,
    },
}