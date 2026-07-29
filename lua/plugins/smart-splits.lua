return {
  'mrjones2014/smart-splits.nvim',
  opts = {
    multiplexer_integration = 'tmux',
  },
  keys = {
    { '<M-h>',       function() require('smart-splits').move_cursor_left()     end, mode = {       'n', 'i', 't' }, desc = 'Move split left'  },
    { '<M-j>',       function() require('smart-splits').move_cursor_down()     end, mode = {       'n', 'i', 't' }, desc = 'Move split down'  },
    { '<M-k>',       function() require('smart-splits').move_cursor_up()       end, mode = {       'n', 'i', 't' }, desc = 'Move split up'    },
    { '<M-l>',       function() require('smart-splits').move_cursor_right()    end, mode = {       'n', 'i', 't' }, desc = 'Move split right' },
    { '<Up>',        function() require('smart-splits').resize_up()            end, desc = 'Resize up'    },
    { '<Down>',      function() require('smart-splits').resize_down()          end, desc = 'Resize down'  },
    { '<Left>',      function() require('smart-splits').resize_left()          end, desc = 'Resize left'  },
    { '<Right>',     function() require('smart-splits').resize_right()         end, desc = 'Resize right' },
    { '<leader>wp',  function() require('smart-splits').move_cursor_previous() end, desc = 'Move cursor previous window'},
    { '<leader>wsh', function() require('smart-splits').swap_buf_left()       end,  desc = 'Swap buffer left'},
    { '<leader>wsj', function() require('smart-splits').swap_buf_down()       end,  desc = 'Swap buffer down'},
    { '<leader>wsk', function() require('smart-splits').swap_buf_up()         end,  desc = 'Swap buffer up'},
    { '<leader>wsl', function() require('smart-splits').swap_buf_right()      end,  desc = 'Swap buffer right'},
  },
}
