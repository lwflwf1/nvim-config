-- Right-side scrollbar: viewport position + mouse-draggable + signs
-- (diagnostics/search/gitsigns).
-- Chose scrollview over nvim-scrollbar: the latter is virt_text-only visuals
-- and cannot be dragged.
return {
  "dstein64/nvim-scrollview",
  event = "VeryLazy",
  opts = {
    -- draw signs (diagnostics/search/gitsigns) in the scrollbar's column, on
    -- top of the handle; the default 'off' pushes signs out of the bar
    signs_scrollbar_overlap = "over",
    -- diagnostic symbols default to vim.diagnostic signs.text, which is two
    -- spaces (width 2) here and would overflow the 1-wide bar -> force
    -- single-width; E/W/I/H shown inside the bar (highlighted by severity)
    diagnostics_error_symbol = "E",
    diagnostics_warn_symbol = "W",
    diagnostics_info_symbol = "I",
    diagnostics_hint_symbol = "H",
    -- defaults are diagnostics/marks/search only; add merge-conflict markers
    -- and TODO/FIXME-style keyword comments
    signs_on_startup = { "diagnostics", "marks", "search", "conflicts", "keywords" },
    -- show for short files too, keeping visuals consistent (scrollview's
    -- default behavior)
    excluded_filetypes = {
      "blink-cmp-menu",
      "dropbar_menu",
      "dropbar_menu_fzf",
      "DressingInput",
      "cmp_docs",
      "cmp_menu",
      "noice",
      "prompt",
      "TelescopePrompt",
    },
  },
  config = function(_, opts)
    require("scrollview").setup(opts)
    -- gitsigns hunk markers; symbols/highlights auto-derive from the gitsigns
    -- config. Wired from the gitsigns config in git.lua (must run after
    -- gitsigns.setup)
  end,
}
