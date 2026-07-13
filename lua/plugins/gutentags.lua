return {
    {
        "ludovicchabant/vim-gutentags",
        event = "VeryLazy",
        config = function()
            local ctags_path
            if vim.g.os == "windows" then
                ctags_path = vim.fn.expand("~") .. "\\bin\\ctags\\ctags.exe"
            else
                ctags_path = "~/.local/bin/ctags"
            end
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
            if vim.g.os == "windows" then
                vim.g.gutentags_ctags_extra_args = {
                    "--tag-relative no",
                    "--fields +aimnSlR",
                    "--extras +qr",
                    "--excmd number",
                }
            else
                vim.g.gutentags_ctags_extra_args = {
                    "--tag-relative=no",
                    "--fields=+aimnSlR",
                    "--extras=+qr",
                    "--excmd=number",
                }
            end
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
