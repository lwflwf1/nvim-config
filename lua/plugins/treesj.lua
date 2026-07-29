return {
  'Wansmer/treesj',
  keys = { '<leader>tt', '<leader>ts', '<leader>tj' },
  dependencies = { 'nvim-treesitter/nvim-treesitter' },
  opts = function()
    local lang_utils = require('treesj.langs.utils')
    local function clear_virtual_brackets(tsj)
      for _, c in ipairs(tsj:children()) do
        if c:type() == 'left_non_bracket' or c:type() == 'right_non_bracket' then
          c:update_text('')
        end
      end
    end
    return {
      use_default_keymaps = false,
      max_join_length = 180,
      cursor_behavior = 'hold',
      dot_repeat = true,
      langs = {
        systemverilog = {
          tf_port_list                        = lang_utils.set_preset_for_args({ both = { non_bracket_node = { left = '(', right = ')' }, last_separator = false, format_tree = clear_virtual_brackets }, split = { last_indent = 'normal' } }),
          list_of_arguments                   = lang_utils.set_preset_for_args({ both = { non_bracket_node = { left = '(', right = ')' }, last_separator = false, format_tree = clear_virtual_brackets }, split = { last_indent = 'normal' } }),
          list_of_ports                       = lang_utils.set_preset_for_args(),
          list_of_port_declarations           = lang_utils.set_preset_for_args(),
          parameter_port_list                 = lang_utils.set_preset_for_args(),
          list_of_port_connections            = lang_utils.set_preset_for_args({ both = { non_bracket_node = { left = '(', right = ')' }, last_separator = false, format_tree = clear_virtual_brackets }, split = { last_indent = 'normal' } }),
          list_of_param_assignments           = lang_utils.set_preset_for_args({ both = { last_separator = true } }),
          list_of_parameter_value_assignments = lang_utils.set_preset_for_args({ both = { non_bracket_node = { left = '(', right = ')' }, last_separator = false, format_tree = clear_virtual_brackets }, split = { last_indent = 'normal' } }),
          concatenation                       = lang_utils.set_preset_for_list(),
          assignment_pattern                  = lang_utils.set_preset_for_dict(),
          seq_block = {
            both = { non_bracket_node = { left = 'begin', right = 'end' } },
            join = { space_in_brackets = true },
          },
        },
      },
    }
  end,
  config = function(_, opts)
    require('treesj').setup(opts)
    local tsj = require('treesj')
    vim.keymap.set('n', '<leader>tt', tsj.toggle, { desc = 'Treesj toggle' })
    vim.keymap.set('n', '<leader>ts', tsj.split,  { desc = 'Treesj split' })
    vim.keymap.set('n', '<leader>tj', tsj.join,   { desc = 'Treesj join' })
  end,
}
