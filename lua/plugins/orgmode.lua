return {
  {
    "nvim-orgmode/orgmode",
    event = "VeryLazy",
    ft = { "org" },
    dependencies = {
      "nvim-lua/plenary.nvim",
      { "nvim-orgmode/telescope-orgmode.nvim", dependencies = "nvim-telescope/telescope.nvim" },
      "nvim-orgmode/org-bullets.nvim",
      "lukas-reineke/headlines.nvim",
      "danilshvalov/org-modern.nvim",
      "seflue/org-link.nvim",
    },
    opts = {
      org_agenda_files = vim.fn.expand("~/orgfiles/**/*"),
      org_default_notes_file = vim.fn.expand("~/orgfiles/refile.org"),
      org_archive_location = vim.fn.expand("~/orgfiles/.archive/%s_archive::"),

      org_todo_keywords = { "TODO(t)", "NEXT(n)", "WAIT(w)", "HOLD(h)", "|", "DONE(d)", "CANC(c)" },
      org_todo_repeat_to_state = "NEXT",
      org_todo_keyword_faces = {
        TODO = ":foreground #f38ba8 :weight bold",
        NEXT = ":foreground #a6e3a1 :weight bold",
        WAIT = ":foreground #f9e2af :weight bold",
        HOLD = ":foreground #6c7086 :slant italic",
        CANC = ":foreground #6c7086 :strike through",
        DONE = ":foreground #a6e3a1",
      },

      org_log_done = "time",
      org_log_repeat = "time",
      org_log_into_drawer = "LOGBOOK",

      org_effort_property = "EFFORT",
      org_agenda_clockreport = true,

      org_time_stamp_rounding_minutes = 5,

      org_tags_column = -80,
      org_use_tag_inheritance = true,
      org_tags_exclude_from_inheritance = { "PROJECT", "INBOX" },

      org_hide_leading_stars = false,
      org_startup_folded = "overview",
      org_adapt_indentation = true,
      org_startup_indented = false,
      org_cycle_separator_lines = 2,
      org_blank_before_new_entry = { heading = true, plain_list_item = false },

      win_split_mode = "float",
      win_border = "rounded",
      org_agenda_min_height = 20,

      org_agenda_span = "week",
      org_agenda_start_on_weekday = 1,
      org_deadline_warning_days = 14,
      org_agenda_hide_empty_blocks = true,
      org_agenda_remove_tags = false,

      org_notifications = {
        enabled = true,
        cron_enabled = true,
        repeat_enabled = true,
        deadline_warning_days = 14,
      },

      org_custom_exports = {
        p = {
          label = "Export to PDF (pandoc)",
          action = function(exporter)
            local f = vim.api.nvim_buf_get_name(0)
            local t = vim.fn.fnamemodify(f, ":p:r") .. ".pdf"
            return exporter({ "pandoc", f, "-o", t, "--pdf-engine=xelatex" }, t)
          end,
        },
        h = {
          label = "Export to HTML (pandoc)",
          action = function(exporter)
            local f = vim.api.nvim_buf_get_name(0)
            local t = vim.fn.fnamemodify(f, ":p:r") .. ".html"
            return exporter({ "pandoc", f, "-o", t, "--standalone" }, t)
          end,
        },
        m = {
          label = "Export to Markdown",
          action = function(exporter)
            local f = vim.api.nvim_buf_get_name(0)
            local t = vim.fn.fnamemodify(f, ":p:r") .. ".md"
            return exporter({ "pandoc", f, "-o", t, "-t", "gfm" }, t)
          end,
        },
      },

      org_capture_templates = {
        t = { description = "Task", template = "* TODO %?\n  %u", target = "~/orgfiles/inbox.org" },
        n = { description = "Next action", template = "* NEXT %?\n  %u", target = "~/orgfiles/inbox.org" },
        j = { description = "Journal entry", template = "%?", target = "~/orgfiles/journal.org", datetree = true },
        J = { description = "Journal with time", template = "* %U\n\n%?", target = "~/orgfiles/journal.org", datetree = true },
        p = { description = "Project", template = "* %?\n  :PROPERTIES:\n  :CATEGORY: %^{Category|work|personal|study}\n  :END:", target = "~/orgfiles/agenda.org" },
        e = { description = "Scheduled event", template = "* %?\n  SCHEDULED: %^T", target = "~/orgfiles/agenda.org" },
        d = { description = "Deadline task", template = "* TODO %?\n  DEADLINE: %^T", target = "~/orgfiles/agenda.org" },
        E = { description = "Repeating task", template = "* TODO %?\n  SCHEDULED: %^T\n  :PROPERTIES:\n  :LAST_REPEAT: %U\n  :END:", target = "~/orgfiles/agenda.org" },
        w = { description = "Waiting", template = "* WAIT %?\n  :PROPERTIES:\n  :WAITING_FOR: %^{Who|}\n  :WAITING_ON: %^{What|}\n  :END:", target = "~/orgfiles/agenda.org" },
        h = { description = "Hold", template = "* HOLD %?\n  :PROPERTIES:\n  :REASON: %^{Why|}\n  :END:", target = "~/orgfiles/agenda.org" },
        i = { description = "Idea", template = "* %?\n  :PROPERTIES:\n  :CREATED: %U\n  :END:", target = "~/orgfiles/notes/ideas.org" },
        r = { description = "Reading note", template = "* %^{Title} - %^{Author}\n  Source: %^{Source|}\n  %?", target = "~/orgfiles/notes/reading.org" },
        m = { description = "Meeting", template = "* %^{Meeting} <%<%Y-%m-%d>>\n  Attendees: %^{Attendees|}\n  %?", target = "~/orgfiles/notes/meetings.org", datetree = true },
        b = { description = "Bookmark", template = "* [[%^{URL}][%^{Title}]]\n  %?", target = "~/orgfiles/notes/bookmarks.org" },
        P = { description = "Project from template", template = vim.fn.join(vim.fn.readfile(vim.fn.expand("~/orgfiles/projects/_template.org")), "\n"), target = "~/orgfiles/projects/" },
      },

      org_agenda_custom_commands = {
        a = { description = "Today + Tomorrow", types = { { type = "agenda", org_agenda_span = "day", org_agenda_overriding_header = "Today" }, { type = "agenda", org_agenda_start_day = "+1d", org_agenda_span = "day", org_agenda_overriding_header = "Tomorrow" } } },
        w = { description = "Week view", types = { { type = "agenda", org_agenda_span = "week" } } },
        m = { description = "Month view", types = { { type = "agenda", org_agenda_span = "month" } } },
        y = { description = "Year view", types = { { type = "agenda", org_agenda_span = "year" } } },
        t = { description = "All TODOs", types = { { type = "tags_todo", match = "-CANC-DONE", org_agenda_overriding_header = "All unfinished tasks" } } },
        p = { description = "Projects", types = { { type = "tags_todo", match = "+PROJECT/-NEXT-DONE-CANC", org_agenda_overriding_header = "Active projects" } } },
        n = { description = "Next actions", types = { { type = "tags_todo", match = "+NEXT", org_agenda_overriding_header = "Next actions" } } },
        W = { description = "Waiting", types = { { type = "tags_todo", match = "+WAIT", org_agenda_overriding_header = "Waiting for..." } } },
        H = { description = "On hold", types = { { type = "tags_todo", match = "+HOLD", org_agenda_overriding_header = "On hold" } } },
        S = { description = "Stuck projects", types = { { type = "tags_todo", match = "+PROJECT-TODO-NEXT-WAIT-HOLD-DONE-CANC", org_agenda_overriding_header = "Stuck projects (no next action)" } } },
        A = { description = "Archived", types = { { type = "tags", match = "+ARCHIVE", org_agenda_overriding_header = "Archived items" } } },
        d = { description = "Recently done", types = { { type = "tags_todo", match = "+DONE", org_agenda_overriding_header = "Recently completed (7 days)" } } },
      },

      mappings = { org_return_uses_meta_return = true },
    },
    config = function(_, opts)
      require("orgmode").setup(opts)
      vim.lsp.enable("org")

      pcall(function()
        require("org-bullets").setup({
          concealcursor = true,
          symbols = {
            list = "•",
            headlines = { "◉", "○", "✸", "✿" },
            checkboxes = {
              todo = { " " },
              done = { "✓" },
              half = { "" },
            },
          },
        })
      end)

      local bullet_ns = vim.api.nvim_create_namespace("org-bullets")

      vim.api.nvim_create_autocmd("InsertEnter", {
        pattern = "*.org",
        callback = function()
          if vim.bo.filetype ~= "org" then return end
          vim.api.nvim_buf_clear_namespace(0, bullet_ns, 0, -1)
        end,
      })

      vim.api.nvim_create_autocmd("InsertLeave", {
        pattern = "*.org",
        callback = function()
          if vim.bo.filetype ~= "org" then return end
          vim.schedule(function() vim.cmd("redraw!") end)
        end,
      })

      pcall(function()
        local Menu = require("org-modern.menu")
        require("orgmode").setup({
          ui = { menu = { handler = function(data) Menu:new():open(data) end } },
        })
      end)

      pcall(function()
        require("headlines").setup({
          markdown = { query = {} },
          org = {
            headline_highlights = {},
            code_block_highlight = "CodeBlock",
            dash_highlight = "Dash",
            fat_headlines = false,
          },
        })
      end)

      pcall(function()
        require("org-link").setup({ auto_link_completion = true })
      end)


      local function org_map(mode, lhs, rhs, desc)
        vim.keymap.set(mode, lhs, rhs, { buffer = 0, silent = true, desc = desc })
      end

      vim.api.nvim_create_autocmd("FileType", {
        pattern = "org",
        callback = function()
          -- Insert mode
          org_map("i", "<S-CR>", '<cmd>lua require("orgmode").action("org_mappings.meta_return")<CR>', "Meta return")
          org_map("i", "<C-t>", "* TODO ", "Insert TODO")
          org_map("i", "<C-l>", "- ", "Insert list item")
          org_map("i", "<C-x>", "- [ ] ", "Insert checkbox")
          vim.keymap.set("i", "<C-d>", function()
            return "<" .. os.date("%Y-%m-%d %a") .. ">"
          end, { buffer = 0, silent = true, expr = true, desc = "Insert date" })
          vim.keymap.set("i", "<C-p>", function()
            return "<" .. os.date("%Y-%m-%d %a %H:%M") .. ">"
          end, { buffer = 0, silent = true, expr = true, desc = "Insert date+time" })
          org_map("i", "<C-;>", " :", "Insert tag prefix")

          -- Normal mode extras
          org_map("n", "<Leader>ov", ":OrgColumns toggle<CR>", "Column view")
          org_map("n", "<Leader>ow", ":!wc -w %<CR>", "Word count")
          org_map("n", "<Leader>os", ":setlocal spell! spelllang=en<CR>", "Toggle spell")

          org_map("n", "<Leader>oTt", ":OrgTableToggle<CR>", "Table editor")
          org_map("n", "<Leader>oTf", ":OrgTableFormula<CR>", "Table formula")
          org_map("n", "<Leader>oTa", ":OrgTableAlign<CR>", "Table align")
          org_map("n", "<Leader>oTr", ":OrgTableInsertRow<CR>", "Insert row")
          org_map("n", "<Leader>oTR", ":OrgTableDeleteRow<CR>", "Delete row")
          org_map("n", "<Leader>oTc", ":OrgTableInsertCol<CR>", "Insert col")
          org_map("n", "<Leader>oTC", ":OrgTableDeleteCol<CR>", "Delete col")
        end,
      })

      vim.keymap.set("n", "<Leader>oj", ':e ~/orgfiles/journal.org<CR>', { desc = "Journal" })

      vim.api.nvim_create_autocmd({ "BufLeave", "InsertLeave" }, {
        pattern = { "*.org", "*.org_archive" },
        callback = function()
          local bufnr = vim.api.nvim_get_current_buf()
          if vim.bo[bufnr].modified and vim.bo[bufnr].buftype == "" then
            vim.cmd("silent! write")
          end
        end,
      })

      vim.api.nvim_create_autocmd("VimEnter", {
        callback = function()
          local welcome = vim.fn.expand("~/orgfiles/README.org")
          if vim.fn.filereadable(welcome) == 1 and #vim.api.nvim_list_tabpages() == 1 then
            vim.schedule(function() vim.cmd("tabedit " .. welcome) end)
          end
        end,
        once = true,
      })
    end,
  },
}
