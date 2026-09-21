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
    },
    -- The bundled picker UI is intentionally unused: ff/fz/fw/fn/fo go through
    -- snacks.picker sources driven by fff's programmatic API — but only inside a
    -- project; outside one they fall back to snacks' native rg (fzf.lua).
}
