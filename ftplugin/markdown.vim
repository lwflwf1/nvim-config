" Description:   markdown ftplugin
" Maintainer:    lwflwf1
" Website:       https://github.com/lwflwf1/vimrc
" Created Time:  2021-04-30 15:16:12
" Last Modified: 2021-08-17 00:57:07
" File:          markdown.vim
" License:       MIT

inoremap <buffer> <m-1> #<space>
inoremap <buffer> <m-2> ##<space>
inoremap <buffer> <m-3> ###<space>
inoremap <buffer> <m-4> ####<space>
inoremap <buffer> <m-5> #####<space>
inoremap <buffer> <m-6> ######<space>
inoremap <buffer> <m-b> **** <++><esc>7ha
inoremap <buffer> <m-`> `` <++><esc>6ha
inoremap <buffer> <m-c> ```<cr>```<cr><++><esc>2kA
inoremap <buffer> <m-p> ![](<++>)<cr><++><esc>k$7ha
inoremap <buffer> <m-u> [](<++>)<cr><++><esc>k$7ha
