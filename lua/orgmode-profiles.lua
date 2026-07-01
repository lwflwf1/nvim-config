local M = {}
local current = "personal"

function M.set(profile)
  current = profile
  local agenda = profile == "work" and "~/orgfiles-work/**/*" or "~/orgfiles/**/*"
  local notes  = profile == "work" and "~/orgfiles-work/refile.org" or "~/orgfiles/refile.org"
  pcall(function()
    require("orgmode").setup({ org_agenda_files = agenda, org_default_notes_file = notes })
  end)
  vim.notify("Switched to profile: " .. profile)
end

function M.toggle()
  M.set(current == "work" and "personal" or "work")
end

return M
