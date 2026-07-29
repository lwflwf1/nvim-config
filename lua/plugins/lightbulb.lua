return {
  {
    "kosayoda/nvim-lightbulb",
    event = "LspAttach",
    opts = {
      autocmd = { enabled = true },
      sign = { text = "󰌶", hl = "DiagnosticWarn" },
      ignore = {
        ft = { "oil", "neo-tree", "TelescopePrompt" },
      },
    },
  },
}
