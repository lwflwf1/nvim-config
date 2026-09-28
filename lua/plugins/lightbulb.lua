return {
  {
    "kosayoda/nvim-lightbulb",
    event = "LspAttach",
    opts = {
      autocmd = { enabled = true },
      sign = { text = "󰌶", hl = "DiagnosticWarn" },
      ignore = {
        ft = { "snacks_picker_list", "neo-tree", "TelescopePrompt" },
      },
    },
  },
}
