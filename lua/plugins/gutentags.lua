return {
    {
        "ludovicchabant/vim-gutentags",
        event = "VeryLazy",
        config = function()
            local ctags_path = vim.fn.expand(
                vim.g.os == "windows" and "~/bin/ctags/ctags.exe" or "~/.local/bin/ctags"
            )
            if vim.fn.executable(ctags_path) ~= 1 then
                vim.notify("ctags not found at " .. ctags_path .. ", gutentags disabled", vim.log.levels.WARN)
                vim.g.gutentags_enabled = 0
                return
            end

            vim.g.gutentags_ctags_executable = ctags_path
            vim.g.gutentags_project_root = require("config.root_markers")
            vim.g.gutentags_add_default_project_roots = 1
            vim.g.gutentags_generate_on_new = 1
            vim.g.gutentags_generate_on_missing = 1
            vim.g.gutentags_generate_on_write = 1
            vim.g.gutentags_generate_on_empty = 1
            vim.g.gutentags_ctags_extra_args = {
                "--tag-relative=yes",
                "--fields=+aimnSlR",
                "--extras=+qr",
                "--excmd=number",
            }
            vim.g.gutentags_trace = 0
            vim.g.gutentags_exclude_filetypes = { "gitcommit", "gitrebase", "help", "nerdtree" }
            vim.g.gutentags_ctags_exclude = {
                "*.git/*", "*.svn/*", "*.hg/*", "cache/*", "build/*",
                "node_modules/*", "dist/*", "bin/*", "obj/*", "vendor/*",
                ".vscode/*", "*.min.js", "*.min.css", "*.map", "*.o", "*.obj",
            }
        end,
    },
}
