; Block openers: nodes that start on the anchor line and span multiple lines.
; The node that STARTS on the opening line indents everything after it, so
; contents-only nodes (tf_port_list, list_of_arguments, ...) must NOT be
; marked too: that would double-indent their continuation lines.
[
  (checker_declaration)
  (class_declaration)
  (interface_class_declaration)
  (package_declaration)
  (constraint_declaration)
  (function_declaration)
  (task_declaration)
  (modport_declaration)
  (property_declaration)
  (sequence_declaration)
  (covergroup_declaration)
  (clocking_declaration)
  (specify_block)
  (generate_region)
  (generate_block)
  (initial_construct)
  (always_construct)
  (final_construct)
  (par_block)
  (conditional_statement)
  (loop_statement)
  (case_statement)
  (case_item)
  (randcase_statement)
  (randcase_item)
  (class_constructor_declaration)
  (data_type)
] @indent.begin

; Multi-line brace groups (concatenations / assignment patterns / streams).
[
  (concatenation)
  (constant_concatenation)
  (multiple_concatenation)
  (constant_multiple_concatenation)
  (module_path_concatenation)
  (module_path_multiple_concatenation)
  (assignment_pattern)
  (stream_concatenation)
  (streaming_concatenation)
  (empty_unpacked_array_concatenation)
] @indent.begin

; Nodes that own their parentheses (the list/header node includes '(' ')').
[
  (list_of_ports)
  (list_of_port_declarations)
  (parameter_port_list)
  (hierarchical_instance)
  (parameter_value_assignment)
  (tf_call)
  (system_tf_call)
  (method_call_body)
] @indent.begin

; Dedent the ')' that closes such a node (the ')' must be a direct child).
(list_of_ports ")" @indent.branch @indent.end)
(list_of_port_declarations ")" @indent.branch @indent.end)
(parameter_port_list ")" @indent.branch @indent.end)
(hierarchical_instance ")" @indent.branch @indent.end)
(parameter_value_assignment ")" @indent.branch @indent.end)
(tf_call ")" @indent.branch @indent.end)
(system_tf_call ")" @indent.branch @indent.end)
(method_call_body ")" @indent.branch @indent.end)
(function_body_declaration ")" @indent.branch @indent.end)
(task_body_declaration ")" @indent.branch @indent.end)
(property_declaration ")" @indent.branch @indent.end)
(sequence_declaration ")" @indent.branch @indent.end)

; begin/end directly inside task/function/fork bodies.
(task_body_declaration
  (statement_or_null
    (statement
      (statement_item
        (seq_block) @indent.begin))))
(function_statement
  (statement
    (statement_item
      (seq_block) @indent.begin)))
(par_block
  (statement_or_null
    (statement
      (statement_item
        (seq_block) @indent.begin))))

; do ... while: the trailing 'while' is a direct sibling of 'do', so this
; cannot match a plain while-loop opener (which has no 'do' child).
(loop_statement "do" "while" @indent.branch @indent.end)

[
  "end"
  "endchecker"
  "endclass"
  "endpackage"
  "endfunction"
  "endtask"
  "endproperty"
  "endsequence"
  "endgroup"
  "endcase"
  "endclocking"
  "endspecify"
  "endgenerate"
  "else"
  "}"
  "join"
  "join_any"
  "join_none"
] @indent.branch @indent.end

[
  (one_line_comment)
  (block_comment)
] @indent.auto
