return {
  {
    "MagicDuck/grug-far.nvim",
    cmd = { "GrugFar", "GrugFarWithin" },
    keys = {
      { "<leader>fx", "<cmd>GrugFar<cr>", mode = {"n"}, desc = "Find and Replace" },
      { "<leader>fx", "<cmd>GrugFarWithin<cr>", mode = {"v"}, desc = "Find and Replace" },
    },
    opts = {
      -- follow symlinks in searches/replacements (the box tree is full of links)
      engines = {
        ripgrep = {
          extraArgs = '--follow',
        },
      },
    },
    config = function()
      -- mini.keymap's `jj` combo replays <BS><BS><Esc> via nvim_input, which
      -- misfires in the grug-far buffer (jj stays inserted, insert mode exits).
      -- Disable the combo machinery here and use a clean buffer-local mapping.
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "grug-far",
        callback = function()
          vim.b.minikeymap_disable = true
          vim.keymap.set("i", "jj", "<Esc>", { buffer = true })
        end,
      })
    end,
  },
}
