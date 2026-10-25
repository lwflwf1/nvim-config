return {
    "dmtrKovalenko/fff",
    -- Downloads the prebuilt mlua shared library for this platform;
    -- falls back to cargo build if the download fails.
    build = function() require("fff.download").download_or_build_binary() end,
    lazy = false, -- the engine lazy-initialises itself
    -- RHEL6 never uses fff (see init.lua's vim.g.fff_mode + AGENTS.md): its search
    -- is a synchronous FFI call, and plugin/fff.lua would otherwise kick off its
    -- own indexing of the big NFS tree on UIEnter. Disabling the spec means the
    -- plugin file never runs -> no indexing, no autocmds, no .so loaded.
    enabled = not vim.g.is_rhel6,
    opts = {
        -- RHEL6 / Windows project trees live behind symlinks
        follow_symlinks = true,
        -- Do NOT index at startup. The plugin's UIEnter hook roots the index at
        -- the CWD, i.e. wherever nvim was launched -- often $HOME. That scan
        -- content-indexes everything it finds (minutes here, because of the
        -- model files), and ANY re-root while it is still in flight wedges fff:
        -- the new picker keeps is_scanning = true and every search returns 0
        -- until nvim restarts (reproduced; scan_files() and a second re-root do
        -- not heal it). With lazy_sync the index starts at the first pick, when
        -- auto-cwd has already chdir'd to the project root.
        lazy_sync = true,
    },
    -- The bundled picker UI is intentionally unused: ff/fz/fw/fn/fo go through
    -- snacks.picker sources driven by fff's programmatic API — but only inside a
    -- project; outside one they fall back to snacks' native rg (fzf.lua).
}
