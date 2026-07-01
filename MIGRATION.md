# Neovim 配置修改清单

## 修改 1：core/options.lua — 删除废弃/冗余选项

### 第 19 行：删除 opt.encoding
```lua
-- 删除以下行
opt.encoding = "utf-8"
```
原因：Neovim 始终使用 UTF-8，此选项只读，设置无效。

### 第 44 行：修改 showtabline
```lua
-- 修改前
opt.showtabline = 2

-- 修改后
opt.showtabline = 0
```
原因：bufferline.nvim 接管 tabline，原生 tabline 应关闭。

### 第 58 行：删除 opt.startofline
```lua
-- 删除以下行
opt.startofline = false
```
原因：Neovim 0.12 已移除此选项。

---

## 修改 2：config/lsp.lua — 修复废弃 API

### 第 17 行：vim.lsp.util.set_qflist → vim.fn.setqflist
```lua
-- 修改前
vim.lsp.util.set_qflist(vim.lsp.util.locations_to_items(result))

-- 修改后
vim.fn.setqflist(vim.lsp.util.locations_to_items(result))
```
原因：vim.lsp.util.set_qflist() 在 Neovim 0.11 中已废弃。

### 第 20-22 行：vim.lsp.util.jump_to_location → vim.lsp.util.show_document
```lua
-- 修改前
vim.lsp.util.jump_to_location(
    type(result) == "table" and result[1] or result
)

-- 修改后
vim.lsp.util.show_document({
    location = type(result) == "table" and result[1] or result,
    focus = true,
})
```
原因：vim.lsp.util.jump_to_location() 在 Neovim 0.11 中已废弃。

### 第 124-129 行：diagnostic signs 格式
```lua
-- 修改前
signs = {
    severity = {
        [vim.diagnostic.severity.ERROR] = { sign_text = "  " },
        [vim.diagnostic.severity.WARN] = { sign_text = "  " },
        [vim.diagnostic.severity.INFO] = { sign_text = "  " },
        [vim.diagnostic.severity.HINT] = { sign_text = "  " },
    },
},

-- 修改后
signs = {
    text = {
        [vim.diagnostic.severity.ERROR] = "  ",
        [vim.diagnostic.severity.WARN] = "  ",
        [vim.diagnostic.severity.INFO] = "  ",
        [vim.diagnostic.severity.HINT] = "  ",
    },
},
```
原因：Neovim 0.12 的 vim.diagnostic.config() signs 使用 `text` 而非 `sign_text`。

---

## 修改 3：plugins/cmp.lua — 修复废弃 API

### 第 20 行：nvim_buf_get_option → vim.bo
```lua
-- 修改前
if vim.api.nvim_buf_get_option(0, "buftype") == "prompt" then

-- 修改后
if vim.bo[0].buftype == "prompt" then
```
原因：vim.api.nvim_buf_get_option() 在 Neovim 0.10 中已废弃。

---

## 修改 4：plugins/formatter.lua — conform v7 推荐格式

### opts 中新增 default_format_opts
```lua
-- 修改前
opts = {
    formatters_by_ft = { ... },
    format_on_save = {
        lsp_format = "fallback",
        timeout_ms = 500,
    },
},

-- 修改后
opts = {
    formatters_by_ft = { ... },
    default_format_opts = {
        lsp_format = "fallback",
    },
    format_on_save = {
        timeout_ms = 500,
    },
},
```
原因：conform.nvim v7 推荐将 lsp_format 移至 default_format_opts，format_on_save 会自动继承。

---

## 修改汇总

| # | 文件 | 位置 | 修改内容 | 必要性 |
|---|------|------|----------|--------|
| 1 | core/options.lua | 第 19 行 | 删除 opt.encoding = "utf-8" | 必须 |
| 2 | core/options.lua | 第 44 行 | opt.showtabline = 2 → 0 | 建议 |
| 3 | core/options.lua | 第 58 行 | 删除 opt.startofline = false | 必须 |
| 4 | config/lsp.lua | 第 17 行 | set_qflist → fn.setqflist | 必须 |
| 5 | config/lsp.lua | 第 20-22 行 | jump_to_location → show_document | 必须 |
| 6 | config/lsp.lua | 第 124-129 行 | diagnostic signs sign_text → text | 必须 |
| 7 | plugins/cmp.lua | 第 20 行 | nvim_buf_get_option → vim.bo | 必须 |
| 8 | plugins/formatter.lua | 第 6-20 行 | 新增 default_format_opts | 建议 |
