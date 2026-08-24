; Override: a bare member access (trans.member / Pkg::member, no argument
; list) must not be highlighted as a function call. Only color as
; function.call when an argument list is present. This wins over the
; bundled nvim-treesitter systemverilog query.
(method_call_body
  (simple_identifier) @variable.member)

(method_call_body
  name: (simple_identifier) @function.call
  (list_of_arguments))

(static_method_call_body
  (simple_identifier) @variable.member)

(static_method_call_body
  name: (simple_identifier) @function.call
  (list_of_arguments))
