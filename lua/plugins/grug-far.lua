return {
  {
    "MagicDuck/grug-far.nvim",
    cmd = { "GrugFar", "GrugFarWithin" },
    keys = {
      { "<leader>fx", "<cmd>GrugFar<cr>", mode = {"n"}, desc = "Find and Replace" },
      { "<leader>fx", "<cmd>GrugFarWithin<cr>", mode = {"v"}, desc = "Find and Replace" },
    },
    opts = {},
  },
}
