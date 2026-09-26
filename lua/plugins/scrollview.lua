-- 右侧滚动条：视口位置 + 可鼠标拖拽 + signs（诊断/搜索/gitsigns）
-- 选 scrollview 而非 nvim-scrollbar：后者是 virt_text 纯视觉，无法拖拽
return {
  "dstein64/nvim-scrollview",
  event = "VeryLazy",
  opts = {
    -- sign（诊断/搜索/gitsigns）画进滚动条同一列，盖在 handle 之上；
    -- 默认 'off' 会把 sign 推到条外
    signs_scrollbar_overlap = "over",
    -- 诊断符号默认取自 vim.diagnostic signs.text，本配置为两空格（宽 2），
    -- 会越出 1 宽的条 → 显式改成单宽；条内显示 E/W/I/H（严重度高亮）
    diagnostics_error_symbol = "E",
    diagnostics_warn_symbol = "W",
    diagnostics_info_symbol = "I",
    diagnostics_hint_symbol = "H",
    -- 默认仅 diagnostics/marks/search；补上 merge 冲突标记 + TODO/FIXME 类注释
    signs_on_startup = { "diagnostics", "marks", "search", "conflicts", "keywords" },
    -- 短文件也显示，保持视觉一致（scrollview 默认同此行为）
    excluded_filetypes = {
      "blink-cmp-menu",
      "dropbar_menu",
      "dropbar_menu_fzf",
      "DressingInput",
      "cmp_docs",
      "cmp_menu",
      "noice",
      "prompt",
      "TelescopePrompt",
    },
  },
  config = function(_, opts)
    require("scrollview").setup(opts)
    -- gitsigns hunk 标记；符号/高亮自动取自 gitsigns 配置，
    -- 在 git.lua 的 gitsigns config 里调用（须在 gitsigns.setup 之后）
  end,
}
