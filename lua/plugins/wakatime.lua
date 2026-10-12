return {
    "wakatime/vim-wakatime",
    -- Not lazy: heartbeats are emitted from CursorHold / BufWritePost / BufEnter,
    -- so a lazily loaded plugin would record nothing.
    lazy = false,
    -- Everything else is installer-owned on purpose. ~/.wakatime.cfg (api_url,
    -- hide_project_folder, sync_ai_disabled) is written by install-offline.sh /
    -- install.ps1, and ~/.wakatime/wakatime-cli is linked from
    -- .local/bin/wakatime-cli-linux-amd64 by install-offline.sh. Neither can be
    -- done from here: `opts` merges *after* plugin/wakatime.vim has already called
    -- require('wakatime').setup(), whose setup_cli() latches the first CLI path it
    -- finds (state.cli_already_setup) -- a later cli_path would leave
    -- state.wakatime_cli pointing nowhere and send_heartbeats() silently drops the
    -- buffer on every event. And a config file should not write files on startup.
    opts = function()
        -- The plugin injects a lualine component and refreshes it with
        -- `wakatime-cli --today` every 60s. That call is network-only
        -- (cmd/today/today.go has no offline branch, it does not touch the queue),
        -- so on an air-gapped box it is ~1440 doomed processes a day for a status
        -- line that stays empty. Every statusline() call re-checks this flag, so it
        -- holds even though opts merge late.
        return { status_bar_enabled = not vim.g.is_rhel6 }
    end,
}