return {
    {
        "andymass/vim-matchup",
        event = "VeryLazy",
        -- Honors b:match_words already set for systemverilog in
        -- after/ftplugin/systemverilog.lua, so % / [% / ]% / a% / i% work
        -- for SV keyword pairs. Treesitter matching is used automatically.
    },
}
