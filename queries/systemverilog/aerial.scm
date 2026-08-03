; Loaded by: aerial.nvim (lua/aerial/backends/treesitter/helpers.lua)
;   vim.treesitter.query.get(lang, "aerial")
; NOTE: refactoring.nvim does NOT use this file. Do NOT delete it.
;-------------------------------------
; Module / Interface / Package
;-------------------------------------
(module_declaration
  (module_ansi_header name: (simple_identifier) @name)
  (#set! "kind" "Module")) @type

(module_declaration
  (module_nonansi_header name: (simple_identifier) @name)
  (#set! "kind" "Module")) @type

(module_declaration
  .
  (simple_identifier) @name
  (#set! "kind" "Module")) @type

(interface_declaration
  (interface_ansi_header name: (simple_identifier) @name)
  (#set! "kind" "Interface")) @type

(interface_declaration
  (interface_nonansi_header name: (simple_identifier) @name)
  (#set! "kind" "Interface")) @type

(interface_declaration
  .
  (simple_identifier) @name
  (#set! "kind" "Interface")) @type

(package_declaration name: (simple_identifier) @name
  (#set! "kind" "Package")) @type

;-------------------------------------
; Clocking
;-------------------------------------
(clocking_declaration name: (simple_identifier) @name
  (#set! "kind" "Clocking")) @type

(clocking_declaration !name
  (#set! "kind" "Clocking")) @type

;-------------------------------------
; Generate
;-------------------------------------
(generate_block name: (simple_identifier) @name
  (#set! "kind" "Block")) @type

(generate_block !name
  (#set! "kind" "Block")) @type

;-------------------------------------
; Parallel block (fork/join)
;-------------------------------------
(par_block
  .
  (simple_identifier)? @name
  (#set! "kind" "Block")) @type

;-------------------------------------
; Class / Constructor / Property
;-------------------------------------
(class_declaration name: (simple_identifier) @name
  (#set! "kind" "Class")) @type

(class_constructor_declaration "new" @name
  (#set! "kind" "Constructor")) @type

(class_property
  (data_declaration
    (list_of_variable_decl_assignments
      (variable_decl_assignment
        name: (simple_identifier) @name) @type))
  (#set! "kind" "Property"))

;-------------------------------------
; Interface class / Covergroup / Assertion
;-------------------------------------
(interface_class_declaration name: (simple_identifier) @name
  (#set! "kind" "Interface")) @type

(covergroup_declaration name: (simple_identifier) @name
  (#set! "kind" "Covergroup")) @type

(property_declaration name: (simple_identifier) @name
  (#set! "kind" "AssertProperty")) @type

;-------------------------------------
; Variable / Net declarations
;-------------------------------------
(data_declaration
  (list_of_variable_decl_assignments
    (variable_decl_assignment
      name: (simple_identifier) @name) @type)
  (#not-has-ancestor? @type class_property)
  (#set! "kind" "Variable"))

(net_declaration
  (list_of_net_decl_assignments
    (net_decl_assignment
      (simple_identifier) @name))
  (#not-has-ancestor? @type class_property)
  (#set! "kind" "Variable")) @type

;-------------------------------------
; Function / Task
;-------------------------------------
(function_declaration
  (function_body_declaration
    name: (simple_identifier) @name)
  (#set! "kind" "Function")) @type

(function_prototype name: (simple_identifier) @name
  (#set! "kind" "Function")) @type

(task_declaration
  (task_body_declaration
    name: (simple_identifier) @name)
  (#set! "kind" "Function")) @type

(task_prototype name: (simple_identifier) @name
  (#set! "kind" "Function")) @type

;-------------------------------------
; Constraint
;-------------------------------------
(constraint_declaration
  . (simple_identifier) @name
  (#set! "kind" "Constraint")) @type

(constraint_prototype (simple_identifier) @name
  (#set! "kind" "Constraint")) @type

;-------------------------------------
; Sequential block (begin/end)
;-------------------------------------
(seq_block
  .
  (simple_identifier)? @name
  (#set! "kind" "Block")) @type
