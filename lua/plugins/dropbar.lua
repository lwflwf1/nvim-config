return {
    'Bekaboo/dropbar.nvim',
    lazy = false,
    config = function()
      local configs = require('dropbar.configs')
      local ts_config = configs.opts.sources.treesitter
      table.insert(ts_config.valid_types, 'task')
      table.insert(ts_config.valid_types, 'module')

      -- Add Task icon (task in SV is analogous to function)
      configs.opts.icons.kinds.symbols.Task = '󰊕 '
      -- Link Task highlight to Function (same as function/method)
      local function set_task_hl()
        vim.api.nvim_set_hl(0, 'DropBarIconKindTask', { link = 'Function', default = true })
        vim.api.nvim_set_hl(0, 'DropBarKindTask', { default = true })
        vim.api.nvim_set_hl(0, 'DropBarIconKindTaskNC', { link = 'DropBarIconKindDefaultNC', default = true })
        vim.api.nvim_set_hl(0, 'DropBarKindTaskNC', { default = true })
      end
      set_task_hl()
      vim.api.nvim_create_autocmd('ColorScheme', {
        group = vim.api.nvim_create_augroup('dropbar_task_hl', {}),
        callback = set_task_hl,
      })

      local ts_module = require('dropbar.sources.treesitter')
      local orig_get_symbols = ts_module.get_symbols
      ts_module.get_symbols = function(buf, win, cursor)
        local symbols = orig_get_symbols(buf, win, cursor)
        if #symbols <= 1 then return symbols end
        local deduped = {}
        local last_name = nil
        local last_line = nil
        for _, sym in ipairs(symbols) do
          local name = sym.name and sym.name:gsub('%s*$', '') or ''
          local line = sym.range and sym.range.start and sym.range.start.line
          if name ~= last_name and line ~= last_line then
            table.insert(deduped, sym)
            last_name = name
            last_line = line
          end
        end
        return deduped
      end

      local dropbar_api = require('dropbar.api')
      vim.keymap.set('n', 'gbb', dropbar_api.pick, { desc = 'Pick symbols in winbar' })
      vim.keymap.set('n', 'gbp', dropbar_api.goto_context_start, { desc = 'Go to start of current context' })
      vim.keymap.set('n', 'gbn', dropbar_api.select_next_context, { desc = 'Select next context' })
    end
}
