" Comments
syntax match ralfComment /#.*$/

" Keywords
syntax keyword ralfKeyword register field bytes bits access reset block

" Access modes
syntax keyword ralfAccess rw ro w1t w1c

" @ prefix with number (must be before ralfNumber to avoid conflict)
syntax match ralfSpecial /@0x[0-9a-fA-F]\+\|@[0-9]\+/

" Numbers
syntax match ralfNumber /0x[0-9a-fA-F]\+/
syntax match ralfNumber /\<\d\+\>/

" Names (identifiers)
syntax match ralfName /\<[a-zA-Z_][a-zA-Z0-9_]*\>/

" Braces and parentheses (operator)
syntax match ralfOperator /[{}()]/

" String inside parentheses
syntax region ralfString start="(" end=")" oneline

highlight default link ralfComment   Comment
highlight default link ralfKeyword   Keyword
highlight default link ralfAccess    Constant
highlight default link ralfSpecial   Special
highlight default link ralfNumber    Number
highlight default link ralfName      Identifier
highlight default link ralfOperator  Operator
highlight default link ralfString    String
