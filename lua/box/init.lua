-- box: the personal module. Everything custom lives here -- workflow tooling,
-- plugin patches and small enhancements -- in the mini/snacks style (one
-- submodule per concern). Loaded in two phases from init.lua:
--
--   require("box").setup()       -- early: keymaps / autocmds / commands
--   require("box").setup_late()  -- after lazy: needs plugin rtp / loaded state
--
-- Submodules (lua/box/):
--   project          root detection + auto-cwd + root picker (<leader>p*)
--   sos              SOS source control + generator commands (<leader>s*)
--   sessions         mini.sessions name/save/pick helpers (keymaps + lualine)
--   terminals        picker over live snacks terminals (<leader>fe / :Terminals)
--   toggle_value     SystemVerilog value toggling (<leader>sw)
--   trim             trim trailing whitespace / CRs (<leader>ue)
--   wins             window move/resize (<M-hjkl>, arrows)
--   multicursor      nvim 0.13 multicursor glue (<C-j/k/n/p>, <Esc>)
--   smart_gf         file:line-aware gf/gF
--   winpick          press-a-letter window picker (terminal gf flow)
--   lsp              LSP server config + pick_config
--   parsers          treesitter parser list (data)
--   theme            colorscheme persistence + <leader>uC + lualine theme
--   tools            :ToolInstall / :ToolUpdate
--   neovide          GUI settings (called from ginit.vim)
--   battery          lualine battery helper
--   fff_picker       fff-backed snacks picker sources (patch)
--   notifier_anim    snacks notifier enter/exit animation (patch)
--   sticky           WIP
--   orgmode_profiles org personal/work profile switcher
local M = {}

function M.setup()
    require("box.multicursor").setup()
    require("box.smart_gf").setup()
    require("box.wins").setup()
    require("box.trim").setup()
    require("box.toggle_value").setup()
    require("box.terminals").setup()
    require("box.project").setup()
    require("box.sos").setup()
end

function M.setup_late()
    require("box.theme").setup()
    require("box.lsp").setup()
    require("box.tools")
end

return M
