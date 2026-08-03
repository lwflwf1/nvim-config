return {
  "ThePrimeagen/refactoring.nvim",
  dependencies = { "lewis6991/async.nvim" },
  lazy = false,
  keys = {
    { "<leader>dv", function()
      return require("refactoring.debug").print_var { output_location = "below" } .. "iw"
    end, desc = "Debug print var below", mode = { "n" }, expr = true },
    { "<leader>dv", function()
      return require("refactoring.debug").print_var { output_location = "below" }
    end, desc = "Debug print var below", mode = { "x" }, expr = true },
    { "<leader>dV", function()
      return require("refactoring.debug").print_var { output_location = "above" } .. "iw"
    end, desc = "Debug print var above", mode = { "n" }, expr = true },
    { "<leader>dV", function()
      return require("refactoring.debug").print_var { output_location = "above" }
    end, desc = "Debug print var above", mode = { "x" }, expr = true },
    { "<leader>de", function()
      return require("refactoring.debug").print_exp { output_location = "below" }
    end, desc = "Debug print exp below", mode = { "x", "n" }, expr = true },
    { "<leader>dp", function()
      return require("refactoring.debug").print_loc { output_location = "below" }
    end, desc = "Debug print location", mode = "n", expr = true },
    { "<leader>dc", function()
      return require("refactoring.debug").cleanup { restore_view = true }
    end, desc = "Debug print cleanup", mode = { "x", "n" }, expr = true },
  },
}