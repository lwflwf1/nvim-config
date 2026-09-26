-- 右侧滚动条：显示视口位置 + git hunk 标记（gitsigns 集成）
-- 搜索标记需要 nvim-hlslens（未装），故只接 gitsigns handler
return {
  "petertriho/nvim-scrollbar",
  event = "VeryLazy",
  opts = {
    show = true,
    show_in_active_only = false,
    hide_if_all_visible = false, -- 短文件也显示，保持视觉一致
  },
  config = function(_, opts)
    require("scrollbar").setup(opts)
    require("scrollbar.handlers.gitsigns").setup()
  end,
}
