return {
  "olimorris/codecompanion.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter",
  },
  opts = {
    interactions = {
      chat = {
        adapter = {
          name = "opencode",
        },
      },
    },
  },
  keys = {
    { "<leader>ac", ":CodeCompanionChat<CR>",   mode = { "n", "v" }, desc = "CodeCompanion: Chat" },
    { "<leader>ai", ":CodeCompanion<CR>",       mode = { "n", "v" }, desc = "CodeCompanion: Inline" },
    { "<leader>ax", ":CodeCompanionActions<CR>", mode = { "n", "v" }, desc = "CodeCompanion: Actions" },
  },
}
