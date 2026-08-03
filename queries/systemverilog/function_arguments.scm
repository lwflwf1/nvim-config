; Loaded by: hlargs.nvim (lua/hlargs/parse.lua, ts_get_query(lang, "function_arguments"))
; Used for: highlight function/task argument names.
; NOTE: refactoring.nvim does NOT use this file. Do NOT delete it.
(tf_port_item
  name: (simple_identifier) @definition-parameter)

(parameter_declaration
  (list_of_param_assignments
    (param_assignment
      (simple_identifier) @definition-parameter)))

(local_parameter_declaration
  (list_of_param_assignments
    (param_assignment
      (simple_identifier) @definition-parameter)))
