; extends

; Fix: task name not highlighted when class_scope is present
(task_body_declaration
  (class_scope
    (class_type
      (simple_identifier)))
  name: (simple_identifier) @function
  (simple_identifier)? @label)
