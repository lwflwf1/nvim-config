; extends
[
  (module_declaration)
  (interface_declaration)
  (class_declaration)
  (interface_class_declaration)
  (package_declaration)
  (program_declaration)
  (function_declaration)
  (task_declaration)
  (class_constructor_declaration)
  (covergroup_declaration)
  (initial_construct)
  (final_construct)
  (loop_statement)
  (par_block)
  (generate_block)
] @context

; The plugin's own SV query only has `hierarchical_instance`, so a multi-line
; instantiation header (instance_type / parameter overrides) scrolled off the
; top showed nothing identifying WHICH module was being instantiated.
(module_instantiation) @context

; `ifdef/`else/`endif are `conditional_compilation_directive` SIBLINGS of the
; code they guard, not ancestors (verified: the ancestor chain of a line inside
; the region goes straight ... -> module_declaration). So a @context capture on
; the directive can never match the cursor and they cannot be shown at all.
; Left commented out on purpose - capturing them is a no-op, not a fix.
