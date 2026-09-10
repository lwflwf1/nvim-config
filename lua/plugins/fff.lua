return {
    "dmtrKovalenko/fff",
    -- Downloads the prebuilt mlua shared library for this platform;
    -- falls back to cargo build if the download fails.
    build = function() require("fff.download").download_or_build_binary() end,
    lazy = false, -- the engine lazy-initialises itself
    opts = {
        -- RHEL6 / Windows project trees live behind symlinks
        follow_symlinks = true,
    },
    -- The bundled picker UI is intentionally unused: ff/fz/fw go through
    -- snacks.picker sources driven by fff's programmatic API (fzf.lua).
}
