; extends

; --- class-like declarations ---
[
  (module_declaration)
  (interface_declaration)
  (program_declaration)
  (package_declaration)
  (class_declaration)
  (checker_declaration)
] @class.outer

(class_declaration
  "class"
  (_)+
  ";"
  _+ @class.inner
  "endclass")

(module_declaration
  . _+ @class.inner . "endmodule")

(interface_declaration
  . _+ @class.inner . "endinterface")

(program_declaration
  . _+ @class.inner . "endprogram")

(package_declaration
  . _+ @class.inner . "endpackage")

(checker_declaration
  . _+ @class.inner . "endchecker")

; --- function/task without explicit port list (empty parens) ---
(task_declaration
  (task_body_declaration
    "("
    .
    ")"
    .
    ";"
    .
    _+ @function.inner
    .
    "endtask")) @function.outer

(function_declaration
  (function_body_declaration
    "("
    .
    ")"
    .
    ";"
    .
    _+ @function.inner
    .
    "endfunction")) @function.outer

; --- conditional ---
(conditional_statement) @conditional.outer

(case_statement) @conditional.outer

(conditional_statement
  (statement_or_null
    (statement
      (statement_item
        (seq_block
          "begin"
          .
          _+ @conditional.inner
          .
          "end")))))

(conditional_statement
  (statement_or_null
    (statement
      (statement_item) @conditional.inner)))

(case_statement
  (case_item)+ @conditional.inner . "endcase")

; --- loop ---
(loop_statement) @loop.outer

(loop_statement
  [
    (statement_or_null)
    (statement)
  ] @loop.inner)

; --- call ---
(tf_call) @call.outer

(system_tf_call) @call.outer

(tf_call
  (list_of_arguments) @call.inner)

(system_tf_call
  (list_of_arguments) @call.inner)

; --- parameter ---
(tf_port_item) @parameter.inner @parameter.outer

(list_of_arguments
  (_) @parameter.inner @parameter.outer)

; --- assignment ---
[
  (blocking_assignment)
  (nonblocking_assignment)
  (continuous_assign)
] @assignment.outer

; operator_assignment form (all assignment types)
(operator_assignment
  (assignment_operator) . (expression) @assignment.inner)

; simple form (direct children, anonymous = or <=)
(blocking_assignment
  "=" . (_) @assignment.inner)
(nonblocking_assignment
  "<=" . (_) @assignment.inner)

; --- constraint ---
(constraint_declaration) @constraint.outer

(constraint_declaration
  "constraint"
  (simple_identifier)
  .
  (constraint_block
    "{" . _+ @constraint.inner . "}"))

; --- covergroup ---
(covergroup_declaration) @covergroup.outer

(covergroup_declaration
  "covergroup" . (_)+ . ";"
  . (coverage_spec_or_option)* @covergroup.inner
  . "endgroup")

; --- property ---
(property_declaration) @property.outer

(property_declaration
  "property" . (_)+ ";"
  . _+ @property.inner
  . "endproperty")

; --- block (fork/join) ---
(par_block) @block.outer

(par_block
  "fork"
  (statement_or_null)* @block.inner
  (join_keyword)?)
