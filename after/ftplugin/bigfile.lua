-- Snacks' bigfile feature overrides the filetype to "bigfile" for large files,
-- which prevents after/ftplugin/log.lua (vim.wo.wrap = true) from running.
-- Re-apply wrap for log files so they stay readable when treated as big files.
local name = vim.fn.expand("%:t")
if name:match("%.log$") then
  vim.wo.wrap = true
end
