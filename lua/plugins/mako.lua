return {
  "sophacles/vim-bundle-mako",
  ft = { "mako" },
  init = function()
    vim.api.nvim_create_autocmd("FileType", {
      pattern = "mako",
      callback = function(args)
        pcall(vim.treesitter.stop, args.buf)
        vim.b[args.buf].ts_highlight = nil
        vim.bo[args.buf].syntax = "mako"
      end,
    })
  end,
}
