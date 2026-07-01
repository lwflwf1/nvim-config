local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node
local d = ls.dynamic_node
local sn = ls.snippet_node

return {
  s("meet", {
    t("* % "), i(1, "Meeting Title"),
    t({ "", "  Attendees: " }), i(2, "name1, name2"),
    t({ "", "  - " }), i(3, "agenda"),
    t({ "", "  - " }), i(4, "discussion"),
    t({ "", "  - **Action** " }), i(5, "todo"),
  }),

  s("day", {
    t("*** "), f(function() return os.date("%Y-%m-%d %A") end),
    t({ "", "**** " }), f(function() return os.date("%H:%M") end),
    t({ "", "" }), i(0),
  }),

  s("proj", {
    t("* "), i(1, "Project Name"),
    t({ "", "  :PROPERTIES:" }),
    t({ "", "  :CATEGORY: " }), i(2, "personal"),
    t({ "", "  :END:" }),
    t({ "", "" }),
    t({ "", "  ** TODO " }), i(3, "milestone 1"),
    t({ "", "     DEADLINE: " }), f(function() return "<" .. os.date("%Y-%m-%d %a") .. ">" end),
    t({ "", "" }),
    t({ "", "  ** TODO " }), i(4, "milestone 2"),
    t({ "", "" }), i(0),
  }),

  s("src", {
    t({ "#+BEGIN_SRC " }), i(1, "python"),
    t({ "", "" }), i(2, "code here"),
    t({ "", "#+END_SRC" }),
    t({ "", "" }), i(0),
  }),

  s("quote", {
    t({ "#+BEGIN_QUOTE" }),
    t({ "", "" }), i(1, "quote"),
    t({ "", "#+END_QUOTE" }),
    t({ "", "" }), i(0),
  }),

  s("note", {
    t({ "#+BEGIN_NOTE" }),
    t({ "", "" }), i(1, "note"),
    t({ "", "#+END_NOTE" }),
    t({ "", "" }), i(0),
  }),

  s("table", {
    t({ "| " }), i(1, "col1"),
    t(" | "), i(2, "col2"),
    t(" | "), i(3, "col3"),
    t(" |"),
    t({ "", "|---+---+---|" }),
    t({ "", "| " }), i(4, ""),
    t(" | "), i(5, ""),
    t(" | "), i(6, ""),
    t(" |"),
    t({ "", "| " }), i(7, ""),
    t(" | "), i(8, ""),
    t(" | "), i(9, ""),
    t(" |"),
    t({ "", "" }), i(0),
  }),

  s("check", {
    t("- [ ] "), i(0),
  }),

  s("logbook", {
    t({ ":LOGBOOK:" }),
    t({ "", "- State \"DONE\"       from \"TODO\"       [", }),
    f(function() return os.date("%Y-%m-%d %a %H:%M") end),
    t("]"),
    t({ "", ":END:" }),
    t({ "", "" }), i(0),
  }),

  s("prop", {
    t({ ":PROPERTIES:" }),
    t({ "", ":CATEGORY: " }), i(1, "personal"),
    t({ "", ":END:" }),
    t({ "", "" }), i(0),
  }),
}
