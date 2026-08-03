; Loaded by: hlargs.nvim (lua/hlargs/parse.lua, ts_get_query(lang, "function_definition"))
; Used for: highlight function/task declaration name.
; NOTE: refactoring.nvim does NOT use this file. Do NOT delete it.
(function_body_declaration
  name: (simple_identifier)) @definition.function

(task_body_declaration
  name: (simple_identifier)) @definition.function
