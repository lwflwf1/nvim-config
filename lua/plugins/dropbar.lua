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
      -- Align icons with lspkind.nvim
      configs.opts.icons.kinds.symbols.Class     = '󰠱 '
      configs.opts.icons.kinds.symbols.Field     = '󰜢 '
      configs.opts.icons.kinds.symbols.File      = '󰈙 '
      configs.opts.icons.kinds.symbols.Module    = ' '
      configs.opts.icons.kinds.symbols.Property  = '󰜢 '
      configs.opts.icons.kinds.symbols.Reference = '󰈇 '
      configs.opts.icons.kinds.symbols.Snippet   = ' '
      configs.opts.icons.kinds.symbols.Struct    = '󰙅 '
      configs.opts.icons.kinds.symbols.Text      = '󰉿 '
      configs.opts.icons.kinds.symbols.Unit      = '󰑭 '
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

      -- SystemVerilog: exact node type -> dropbar kind mapping.
      -- The SV grammar wraps every class member in class_item/class_method/
      -- class_property wrapper nodes. They are deliberately NOT mapped so they
      -- stay transparent and only real declarations surface. (dropbar's own
      -- prefix matching in valid_types would classify class_item/class_method/
      -- class_property as 'class' because they start with the string 'class'.)
      local sv_kinds = {
        class_declaration = 'Class',
        interface_class_declaration = 'Interface',
        module_declaration = 'Module',
        interface_declaration = 'Interface',
        program_declaration = 'Program',
        package_declaration = 'Package',
        function_declaration = 'Function',
        task_declaration = 'Function',
        class_constructor_declaration = 'Constructor',
        class_property = 'Property',
        function_prototype = 'Function',
        task_prototype = 'Function',
        data_declaration = 'Variable',
      }

      -- Extract the declaration identifier from the node text (first capture).
      -- Keyed by node type so task/function can share the 'Function' kind
      -- while keeping their own name rules.
      local sv_name_patterns = {
        class_declaration = '^\\s*\\%(virtual\\s\\+\\)\\?class\\s\\+\\(\\k\\+\\)',
        interface_class_declaration = '^\\s*\\%(virtual\\s\\+\\)\\?interface\\s\\+\\%(class\\s\\+\\)\\?\\(\\k\\+\\)',
        interface_declaration = '^\\s*\\%(virtual\\s\\+\\)\\?interface\\s\\+\\%(class\\s\\+\\)\\?\\(\\k\\+\\)',
        module_declaration = '^\\s*module\\s\\+\\(\\k\\+\\)',
        program_declaration = '^\\s*program\\s\\+\\(\\k\\+\\)',
        package_declaration = '^\\s*package\\s\\+\\(\\k\\+\\)',
        function_declaration = '\\(\\k\\+\\)\\s*(',
        function_prototype = '\\(\\k\\+\\)\\s*(',
        class_constructor_declaration = '\\(\\k\\+\\)\\s*(',
        task_declaration = '^\\s*task\\s\\+\\%(\\%(automatic\\|static\\|extern\\|virtual\\|protected\\|local\\)\\s\\+\\)\\?\\(\\k\\+\\)\\%(::\\(\\k\\+\\)\\)\\?',
        task_prototype = '^\\s*task\\s\\+\\%(\\%(automatic\\|static\\|extern\\|virtual\\|protected\\|local\\)\\s\\+\\)\\?\\(\\k\\+\\)\\%(::\\(\\k\\+\\)\\)\\?',
        class_property = '\\(\\k\\+\\)\\s*\\(\\[[^\\[\\]]*\\]\\s*\\)\\?[;=,]',
        data_declaration = '\\(\\k\\+\\)\\s*\\(\\[[^\\[\\]]*\\]\\s*\\)\\?[;=,]',
      }

      -- For multi-variable declarations (`int a, b;`), find the
      -- simple_identifier whose range covers column `col`.
      local function sv_identifier_at_col(node, buf, col)
        for child in node:iter_children() do
          if child:type() == 'simple_identifier' then
            local _, sc, _, ec = child:range()
            if col >= sc and col <= ec then
              return vim.treesitter.get_node_text(child, buf)
            end
          end
          local found = sv_identifier_at_col(child, buf, col)
          if found then return found end
        end
      end

      local function sv_node_name(node, buf, col)
        local kind = sv_kinds[node:type()]
        if not kind then
          return nil
        end
        local text = vim.treesitter.get_node_text(node, buf):gsub('\n', ' '):gsub('%s+', ' ')
        local m = vim.fn.matchlist(text, sv_name_patterns[node:type()])
        if node:type() == 'class_property' or node:type() == 'data_declaration' then
          -- Try cursor-column-aware lookup for multi-variable declarations
          if col then
            local id = sv_identifier_at_col(node, buf, col)
            if id and id ~= '' then return id end
          end
          -- m[2] is the variable name; m[3] is only the [dimension], which
          -- must never replace the name (e.g. `int x[3] = {...};`)
          return m[2] ~= nil and m[2] ~= '' and m[2] or m[3] or ''
        end
        return m[3] ~= nil and m[3] ~= '' and m[3] or m[2] or ''
      end

      local function sv_valid(node, buf)
        return sv_kinds[node:type()] ~= nil and sv_node_name(node, buf) ~= ''
      end

      -- For multi-variable declarations (e.g. `bit [31:0] hw_val, mask;`),
      -- return the variable_decl_assignment child nodes when there are ≥ 2.
      local function sv_multi_vars(node, buf)
        local t = node:type()
        if t ~= 'data_declaration' and t ~= 'class_property' then
          return nil
        end
        for list in node:iter_children() do
          if list:type() == 'list_of_variable_decl_assignments' then
            local vars = {}
            for va in list:iter_children() do
              if va:type() == 'variable_decl_assignment' then
                vars[#vars + 1] = va
              end
            end
            if #vars >= 2 then return vars end
          end
        end
        return nil
      end

      local function sv_children(node, buf)
        local children = {}
        for child in node:iter_children() do
          if sv_valid(child, buf) then
            local vars = sv_multi_vars(child, buf)
            if vars then
              for _, v in ipairs(vars) do
                children[#children + 1] = v
              end
            else
              children[#children + 1] = child
            end
          else
            vim.list_extend(children, sv_children(child, buf))
          end
        end
        return children
      end

      local function sv_siblings(node, buf, col)
        local siblings = {}

        -- Phase 1: prev siblings (collected in reverse, inserted at front)
        local current = node:prev_sibling()
        while current do
          if sv_valid(current, buf) then
            local vars = sv_multi_vars(current, buf)
            if vars then
              for i = #vars, 1, -1 do
                table.insert(siblings, 1, vars[i])
              end
            else
              table.insert(siblings, 1, current)
            end
          else
            siblings = vim.list_extend(sv_children(current, buf), siblings)
          end
          current = current:prev_sibling()
        end

        -- Phase 2: current node (expanded if multi-var, with col-based idx)
        local idx
        local vars = sv_multi_vars(node, buf)
        if vars then
          local base = #siblings
          for i, v in ipairs(vars) do
            siblings[#siblings + 1] = v
            if col then
              local id = sv_identifier_at_col(v, buf, col)
              if id and id ~= '' then idx = base + i end
            end
          end
          if not idx then idx = #siblings end
        else
          siblings[#siblings + 1] = node
          idx = #siblings
        end

        -- Phase 3: next siblings
        current = node:next_sibling()
        while current do
          if sv_valid(current, buf) then
            local vars = sv_multi_vars(current, buf)
            if vars then
              for _, v in ipairs(vars) do
                siblings[#siblings + 1] = v
              end
            else
              siblings[#siblings + 1] = current
            end
          else
            vim.list_extend(siblings, sv_children(current, buf))
          end
          current = current:next_sibling()
        end

        return siblings, idx
      end

      local bar = require('dropbar.bar')

      local function sv_convert(node, buf, win, col)
        local kind = sv_kinds[node:type()]
        local name = sv_node_name(node, buf, col)

        -- variable_decl_assignment: extract name from first child,
        -- inherit kind from parent declaration.
        if node:type() == 'variable_decl_assignment' then
          for child in node:iter_children() do
            if child:type() == 'simple_identifier' then
              name = vim.treesitter.get_node_text(child, buf)
              break
            end
          end
          if not name or name == '' then return nil end
          local parent = node:parent()
          if parent then parent = parent:parent() end
          if parent then kind = sv_kinds[parent:type()] end
          if not kind then kind = 'Variable' end
        end

        if not kind or name == '' then
          return nil
        end
        local sr, sc, er, ec = node:range()
        return bar.dropbar_symbol_t:new(setmetatable({
          buf = buf,
          win = win,
          name = name,
          icon = configs.opts.icons.kinds.symbols[kind],
          name_hl = 'DropBarKind' .. kind,
          icon_hl = 'DropBarIconKind' .. kind,
          range = {
            start = {
              line = sr,
              character = sc,
            },
            ['end'] = {
              line = er,
              character = ec,
            },
          },
        }, {
          __index = function(self, k)
            if k == 'children' then
              self.children = vim.tbl_map(function(child)
                return sv_convert(child, buf, win)
              end, sv_children(node, buf))
              return self.children
            end

            if k == 'siblings' or k == 'sibling_idx' then
              local siblings, idx = sv_siblings(node, buf, col)
              self.siblings = vim.tbl_map(function(sibling)
                return sv_convert(sibling, buf, win)
              end, siblings)
              self.sibling_idx = idx
              return self[k]
            end
          end,
        }))
      end

      -- Qualifier keywords ('virtual'/'static'/...) are sibling nodes of the
      -- declaration they qualify inside class_method, not ancestors. Jump to
      -- the declaration so the cursor on a qualifier still resolves.
      local sv_qualifier_types = {
        method_qualifier = true,
        class_item_qualifier = true,
        property_qualifier = true,
        random_qualifier = true,
      }

      -- Top-level containers (class/module/program/package/interface).
      -- has_member() returns true only for actual member symbols; containers
      -- themselves do not count so that a trailing-whitespace / comment cursor
      -- that resolves to a container triggers the first-token fallback below.
      local sv_container_types = {
        class_declaration = true,
        interface_class_declaration = true,
        module_declaration = true,
        interface_declaration = true,
        program_declaration = true,
        package_declaration = true,
      }

      -- Bare qualifier keywords ('pure'/'virtual'/'extern') are unnamed
      -- children of class_method, so get_node returns the class_method itself
      -- when the cursor sits on them. Descend to the first real declaration.
      local function sv_descend(node, buf)
        for child in node:iter_children() do
          if sv_valid(child, buf) then
            return child
          end
          local found = sv_descend(child, buf)
          if found then
            return found
          end
        end
      end

      local function sv_resolve(node, buf)
        if node and sv_qualifier_types[node:type()] then
          local sib = node:next_sibling()
          while sib and not sv_kinds[sib:type()] do
            sib = sib:next_sibling()
          end
          if sib then
            return sib
          end
        end
        if node and node:type() == 'class_method' then
          return sv_descend(node, buf) or node
        end
        return node
      end

      -- Walk the ancestor chain and return true when a non-container member
      -- (function / task / property / constructor / prototype) is found.
      local function has_member(n)
        while n do
          local t = n:type()
          if sv_kinds[t] and not sv_container_types[t] then
            return true
          end
          n = n:parent()
        end
        return false
      end

      local utils = require('dropbar.utils')

        local function sv_get_symbols(buf, win, cursor)
          if
            not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_win_is_valid(win)
          then
            return {}
          end

          local ok, parser = pcall(vim.treesitter.get_parser, buf or 0)
          if not ok then
            return {}
          end
          parser:parse()

          local symbols = {}

          local line = vim.api.nvim_buf_get_lines(buf, cursor[1] - 1, cursor[1], false)[1] or ''
          local col = math.min(cursor[2], math.max(#line - 1, 0))
          col = col - (col >= 1 and vim.startswith(vim.fn.mode(), 'i') and 1 or 0)
          -- get_node on leading whitespace returns the outer class_declaration
          -- and hides the member; land on the first non-whitespace char instead.
          local nws = line:find('%S')
          if nws then
            col = math.max(col, nws - 1)
          end
          local pos_node = vim.F.npcall(vim.treesitter.get_node, {
            ft = vim.filetype.match({ buf = buf }),
            bufnr = buf,
            pos = { cursor[1] - 1, col },
          })

          -- Fallback: when the cursor sits on trailing whitespace or a trailing
          -- comment, the resolved chain contains only the container (class/module).
          -- Re-resolve from the first non-whitespace position and prefer it when
          -- it carries a member that the cursor position lacks.
          if nws and col ~= nws - 1 then
            local alt = vim.F.npcall(vim.treesitter.get_node, {
              ft = vim.filetype.match({ buf = buf }),
              bufnr = buf,
              pos = { cursor[1] - 1, nws - 1 },
            })
            if alt then
              local alt_resolved = sv_resolve(alt, buf)
              local pos_resolved = sv_resolve(pos_node, buf)
              if not has_member(pos_resolved) and has_member(alt_resolved) then
                pos_node = alt
              end
            end
          end

          node = sv_resolve(pos_node, buf)

          while node and #symbols < ts_config.max_depth do
            local sym = sv_convert(node, buf, win, col)
            if sym then
              table.insert(symbols, 1, sym)
            end
            node = node:parent()
          end

          utils.bar.set_min_widths(symbols, ts_config.min_widths)
          return symbols
        end

      local ts_module = require('dropbar.sources.treesitter')
      local orig_get_symbols = ts_module.get_symbols
      ts_module.get_symbols = function(buf, win, cursor)
        buf = vim._resolve_bufnr(buf)
        local is_sv = vim.api.nvim_buf_is_valid(buf)
          and vim.bo[buf].filetype == 'systemverilog'
        local symbols
        if is_sv then
          symbols = sv_get_symbols(buf, win, cursor)
        else
          symbols = orig_get_symbols(buf, win, cursor)
        end
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

      -- Override sources: for SystemVerilog, use treesitter (patched) before LSP
      -- so our custom sv_kinds/sv_name_patterns are used instead of LSP symbols.
      -- NOTE: this is bar.sources (source list), NOT sources (per-source config).
      local orig_bar_sources = configs.opts.bar.sources
      configs.opts.bar.sources = function(buf, win)
        if vim.bo[buf].filetype == 'systemverilog' then
          return {
            require('dropbar.sources').path,
            utils.source.fallback({
              require('dropbar.sources').treesitter,
              require('dropbar.sources').lsp,
            }),
          }
        end
        if type(orig_bar_sources) == 'function' then
          return orig_bar_sources(buf, win)
        end
        return orig_bar_sources
      end

      local dropbar_api = require('dropbar.api')
      vim.keymap.set('n', 'gbb', dropbar_api.pick, { desc = 'Pick symbols in winbar' })
      vim.keymap.set('n', 'gbp', dropbar_api.goto_context_start, { desc = 'Go to start of current context' })
      vim.keymap.set('n', 'gbn', dropbar_api.select_next_context, { desc = 'Select next context' })
    end,
}
