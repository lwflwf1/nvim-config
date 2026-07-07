return {
    'Bekaboo/dropbar.nvim',
    -- optional, but required for fuzzy finder support
    dependencies = {
      'nvim-telescope/telescope-fzf-native.nvim',
      build = vim.fn.has("win32") == 1 and "cmake -S. -Bbuild -DCMAKE_BUILD_TYPE=Release && cmake --build build --config Release --target install" or "make"
    },
    config = function()
      local ts_config = require('dropbar.configs').opts.sources.treesitter
      table.insert(ts_config.valid_types, 'task')
      table.insert(ts_config.valid_types, 'module')

      local ts_module = require('dropbar.sources.treesitter')
      local orig_get_symbols = ts_module.get_symbols
      ts_module.get_symbols = function(buf, win, cursor)
        local symbols = orig_get_symbols(buf, win, cursor)
        if #symbols <= 1 then return symbols end
        local deduped = {}
        local last_hl = nil
        for _, sym in ipairs(symbols) do
          if sym.icon_hl ~= last_hl then
            table.insert(deduped, sym)
            last_hl = sym.icon_hl
          end
        end
        return deduped
      end

      local dropbar_api = require('dropbar.api')
      vim.keymap.set('n', '<Leader>;', dropbar_api.pick, { desc = 'Pick symbols in winbar' })
      vim.keymap.set('n', '[;', dropbar_api.goto_context_start, { desc = 'Go to start of current context' })
      vim.keymap.set('n', '];', dropbar_api.select_next_context, { desc = 'Select next context' })
    end
}
