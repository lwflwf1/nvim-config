vim.bo.include = [[^\s*`include]]
vim.bo.formatoptions = "croqlm1"
vim.bo.comments = "sO:*\\ -,mO:*\\ \\ ,exO:*/,s1:/*,mb:*,ex:*/,://"
vim.bo.smartindent = false

vim.b.match_words = [[\<begin\>:\<end\>,\<case\>\|\<casex\>\|\<casez\>\|\<randcase\>:\<endcase\>,\`if\(n\)\?def\>:\`elsif\>:\`else\>:\`endif\>,\<module\>:\<endmodule\>,\<if\>:\<else\>,\<fork\>\s*;\@!$:\<join\(_any\|_none\)\?\>,\<function\>:\<endfunction\>,\<task\>:\<endtask\>,\<specify\>:\<endspecify\>,\<config\>:\<endconfig\>,\<generate\>:\<endgenerate\>,\<primitive\>:\<endprimitive\>,\<table\>:\<endtable\>,\<class\>:\<endclass\>,\<checker\>:\<endchecker\>,\<interface\>:\<endinterface\>,\<clocking\>:\<endclocking\>,\<covergroup\>:\<endgroup\>,\<package\>:\<endpackage\>,\<program\>:\<endprogram\>,\<property\>:\<endproperty\>,\<sequence\>:\<endsequence\>]]
