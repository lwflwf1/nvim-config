return {
    "dmtrKovalenko/fff",
    -- Downloads the prebuilt mlua shared library for this platform;
    -- falls back to cargo build if the download fails.
    build = function() require("fff.download").download_or_build_binary() end,
    lazy = false, -- the engine lazy-initialises itself
    opts = {
        -- RHEL6 / Windows project trees live behind symlinks
        follow_symlinks = true,
        -- NOTE: no `grep.time_budget_ms` here. fzf.lua pages fff grep in small
        -- time-boxed chunks and passes `time_budget_ms` per call (FFF_GREP_CHUNK_MS),
        -- so this global value would be dead config. See AGENTS.md.
    },
    -- The bundled picker UI is intentionally unused: ff/fz/fw/fn/fo go through
    -- snacks.picker sources driven by fff's programmatic API — but only inside a
    -- project; outside one they fall back to snacks' native rg (fzf.lua).
}
