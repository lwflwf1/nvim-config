return {
    {
        "kevinhwang91/nvim-ufo",
        dependencies = { "kevinhwang91/promise-async" },
        init = function()
            vim.o.fillchars = "eob: ,fold: ,foldopen:,foldsep: ,foldclose:"
            vim.o.foldcolumn = "1"
            vim.o.foldlevel = 99
            vim.o.foldlevelstart = 99
            vim.o.foldenable = true
        end,
        config = function()
            local handler = function(virtText, lnum, endLnum, width, truncate)
                local newVirtText = {}
                local suffix = (' 󰁂 %d '):format(endLnum - lnum)
                local sufWidth = vim.fn.strdisplaywidth(suffix)
                local targetWidth = width - sufWidth
                local curWidth = 0
                for _, chunk in ipairs(virtText) do
                    local chunkText = chunk[1]
                    local chunkWidth = vim.fn.strdisplaywidth(chunkText)
                    if targetWidth > curWidth + chunkWidth then
                        table.insert(newVirtText, chunk)
                    else
                        chunkText = truncate(chunkText, targetWidth - curWidth)
                        local hlGroup = chunk[2]
                        table.insert(newVirtText, { chunkText, hlGroup })
                        chunkWidth = vim.fn.strdisplaywidth(chunkText)
                        if curWidth + chunkWidth < targetWidth then
                            suffix = suffix .. (' '):rep(targetWidth - curWidth - chunkWidth)
                        end
                        break
                    end
                    curWidth = curWidth + chunkWidth
                end
                table.insert(newVirtText, { suffix, "MoreMsg" })
                return newVirtText
            end

            require("ufo").setup({
                open_fold_hl_timeout = 150,
                provider_selector = function(bufnr, filetype, buftype)
                    if buftype ~= "" then
                        return ""
                    end
                    if pcall(vim.treesitter.query.get, filetype, "folds") then
                        return { "lsp", "treesitter" }
                    end
                    return { "lsp", "indent" }
                end,
                fold_virt_text_handler = handler,
                close_fold_kinds_for_ft = {
                    default = { "imports", "comment" },
                    json = { "array" },
                    c = { "comment", "region" },
                },
                close_fold_current_line_for_ft = {
                    default = true,
                },
                preview = {
                    win_config = {
                        border = { "", "─", "", "", "", "─", "", "" },
                        winhighlight = "Normal:Folded",
                        winblend = 0,
                    },
                    mappings = {
                        scrollU = "<C-u>",
                        scrollD = "<C-d>",
                        jumpTop = "[",
                        jumpBot = "]",
                    },
                },
            })
        end,
        keys = {
            "za",
            { "zR", function() require("ufo").openAllFolds() end, desc = "Open all folds" },
            { "zM", function() require("ufo").closeAllFolds() end, desc = "Close all folds" },
            { "zr", function() require("ufo").openFoldsExceptKinds() end, desc = "Open folds except kinds" },
            { "zm", function() require("ufo").closeFoldsWith() end, desc = "Close folds with" },
        },
    },
    {
        "kevinhwang91/promise-async",
        lazy = true,
    },
}
