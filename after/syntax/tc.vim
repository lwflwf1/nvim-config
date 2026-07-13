" Comments
syntax match tcComment /#.*$/

" Keywords
syntax keyword tcKeyword IFDEF ELSIF ELSE ENDIF INCLUDE endargs
    \ nextgroup=tcDirectiveColon

" Directive colon (after IFDEF/ELSIF/ELSE/INCLUDE/TAG)
syntax match tcDirectiveColon /\s*:\s*/ contained nextgroup=tcType

" Identifier after directive colon (supports dots for filenames)
syntax match tcType /[_a-zA-Z0-9.]\+/ contained

" Inheritance colon (between child_test and parent_test)
syntax match tcInherit /\s*:\s*/ contained nextgroup=tcParentName

" Parent test name (contained, matched only after tcInherit)
syntax match tcParentName /\w\+_test\>/ contained

" Parameter name (without brackets)
syntax match tcParamName /[_a-zA-Z0-9.]\+\ze\s*:=/ nextgroup=tcAssignOp
syntax match tcParamName /[_a-zA-Z0-9.]\+\ze\s*=\s*/ nextgroup=tcAssignOp
syntax match tcParamName /[_a-zA-Z0-9.]\+\ze\s*:\s\+/ nextgroup=tcAssignOp
syntax match tcParamName /[_a-zA-Z0-9.]\+\ze\s*:\w/ nextgroup=tcAssignOp
syntax match tcParamName /[_a-zA-Z0-9.]\+\ze\s*\[/ nextgroup=tcIndex
syntax match tcParamName /[_a-zA-Z0-9.]\+\ze\s*:\s*"/ nextgroup=tcAssignOp

" Index inside brackets (e.g., [0])
syntax region tcIndex start=/\[/ end=/\]/ contains=tcNumber oneline

" Test name (ends with _test, not followed by assignment operator) - AFTER tcParamName for priority
syntax match tcTestName /\w\+_test\>\ze\s*$/ nextgroup=tcInherit
syntax match tcTestName /\w\+_test\>\ze\s*:\s*\w\+_test/ nextgroup=tcInherit

" Assignment operator
syntax match tcAssignOp /=/ contained nextgroup=tcString,tcNumber
syntax match tcAssignOp /:=/ contained nextgroup=tcString,tcNumber,tcConstant
syntax match tcAssignOp /:\ze\s/ contained nextgroup=tcConstant,tcNumber
syntax match tcAssignOp /:\ze"/ contained nextgroup=tcString
syntax match tcAssignOp /:\ze\w/ contained nextgroup=tcString,tcConstant

" Value (after assignment) - unified as tcConstant
syntax match tcConstant /\S\+/ contained

" Plusarg line (from + to end of line)
syntax region tcPlusArg start=/^\s*+/ end=/\ze\s*$/ contains=tcPlusName,tcAssignOp,tcNumber,tcString

" Plus name (+identifier)
syntax match tcPlusName /+\w\+/ contained

" Plus prefix (+)
syntax match tcSpecial /^\s*+/ contained

" Strings
syntax region tcString start=/"/ end=/"/

" Numbers (decimal, float, hex-like 8-digit)
syntax match tcNumber /\d\+\.\d\+/
syntax match tcNumber /\<[0-9a-fA-F]\{8\}\>/
syntax match tcNumber /\<\d\+\>/

" TAG label (TAG without colon)
syntax match tcLabel /TAG/ nextgroup=tcDirectiveColon

" Operators (standalone)
syntax match tcOperator /:=/

highlight default link tcComment      Comment
highlight default link tcKeyword      Keyword
highlight default link tcTestName     Keyword
highlight default link tcInherit      Operator
highlight default link tcParentName   Keyword
highlight default link tcParamName    Identifier
highlight default link tcIndex        Special
highlight default link tcAssignOp     Operator
highlight default link tcConstant     Constant
highlight default link tcType         Type
highlight default link tcSpecial      Special
highlight default link tcPlusName     Special
highlight default link tcString       String
highlight default link tcNumber       Number
highlight default link tcLabel        Label
highlight default link tcOperator     Operator
highlight default link tcDirectiveColon Operator
highlight default link tcPlusArg      Special
