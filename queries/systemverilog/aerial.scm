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

; Module instances (e.g. `dsi_top #(...) u_old_dsi_top (...)`). Capture the
; instance name's simple_identifier (not the whole name_of_instance) so an
; array instance's unpacked dimension (`[255:0]`) is not part of the name.
(module_instantiation
  instance_type: (simple_identifier)
  (hierarchical_instance
    (name_of_instance (simple_identifier) @name))
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
; Ports (direction-typed; kept distinct from internal Variable signals)
;-------------------------------------
; Non-ANSI body form: `input clk;` / `output [7:0] d;` / `inout pad;`.
; The bare names in a non-ANSI module header (`port` nodes) are intentionally
; NOT captured -- they duplicate these declarations.
(port_declaration
  (input_declaration
    (list_of_port_identifiers (simple_identifier) @name))
  (#set! "kind" "InputPort")) @type

(port_declaration
  (output_declaration
    (list_of_port_identifiers (simple_identifier) @name))
  (#set! "kind" "OutputPort")) @type

(port_declaration
  (inout_declaration
    (list_of_port_identifiers (simple_identifier) @name))
  (#set! "kind" "InoutPort")) @type

; ANSI header form: `module m (input logic clk, output [7:0] d);`.
(ansi_port_declaration
  (_ (port_direction) @dir)
  (simple_identifier) @name
  (#eq? @dir "input")
  (#set! "kind" "InputPort")) @type

(ansi_port_declaration
  (_ (port_direction) @dir)
  (simple_identifier) @name
  (#eq? @dir "output")
  (#set! "kind" "OutputPort")) @type

(ansi_port_declaration
  (_ (port_direction) @dir)
  (simple_identifier) @name
  (#eq? @dir "inout")
  (#set! "kind" "InoutPort")) @type

; Direction omitted (inherited from the previous ANSI port) -- only the
; directionless form has simple_identifier as its first child.
(ansi_port_declaration
  .
  (simple_identifier) @name
  (#set! "kind" "Port")) @type

; Directionless but typed (`input logic clk, logic [3:0] a, b`): the header is
; present but carries no port_direction. Anchor on the header's first child
; being the type so a direction-bearing header does not also match here.
(ansi_port_declaration
  (variable_port_header
    .
    (variable_port_type))
  (simple_identifier) @name
  (#set! "kind" "Port")) @type

(ansi_port_declaration
  (net_port_header
    .
    (net_port_type))
  (simple_identifier) @name
  (#set! "kind" "Port")) @type

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
