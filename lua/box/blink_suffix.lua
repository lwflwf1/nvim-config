-- Conditional "eat the already-typed suffix", i.e. Zed's
-- `completions.lsp_insert_mode = "replace_suffix"` (crates/editor/src/editor.rs,
-- LspInsertMode::ReplaceSuffix) — which blink has no equivalent of
-- (upstream saghen/blink.cmp#1767, #657).
--
-- Why not blink's own knobs:
--   * `completion.keyword.range = 'prefix'` (default) stops the edit at the
--     cursor, so an existing tail is duplicated: editing `creat|eProject()`
--     and accepting `createProject` gives `createProjecteProject()`.
--   * `range = 'full'` always runs the edit to the end of the keyword, so it
--     also eats a tail that has nothing to do with the candidate. Both keyword
--     character classes include `-` (rust: `[\p{L}0-9_-]`,
--     fuzzy/rust/keyword.rs:7-8; lua: iskeyword `@,48-57,_,-,192-255`,
--     fuzzy/lua/keyword.lua:14), so `foo-|bar` loses `bar` even though `bar` is
--     not part of any candidate. `#968` also reported the cursor jumping to
--     line 1 with 'full'.
-- Zed instead *tests* the tail and only then widens the range; that is the
-- behaviour we want, and it is what makes 'full' unsafe here.
--
-- Why 'prefix' stays the baseline: `keyword.range` also feeds `match_suffix`
-- (blink/cmp/fuzzy/init.lua:130), so flipping it to 'full' changes WHICH
-- candidates are offered, not merely what gets edited. Keeping 'prefix' and
-- widening the range here leaves fuzzy matching exactly as it was, so this
-- patch has no effect on the menu contents.
--
-- `text_edits.get_from_item` is the single place blink turns a CompletionItem
-- into an edit range, and every caller goes through the module table
-- (cmp/init.lua for ghost text and for accept, cmp/preview.lua,
-- cmp/libs/luasnip.lua, cmp/libs/vsnip.lua). Wrapping it therefore covers LSP
-- items and keyword sources (lsp, lazydev, buffer, path, snippets) alike, in
-- every mode including the cmdline, without touching any of them.
--
-- Zed's `replace_suffix` idea, not a port of it. It reproduces Zed's *test*
-- (crates/editor/src/editor.rs:11712-11806, case-insensitive, length-aware,
-- empty tail = no-op) but drops Zed's restrictions, on purpose: Zed only tests
-- completions carrying an LSP `InsertReplaceEdit`, so it would not fix the case
-- we care about at all — a buffer/lazydev item has no `textEdit` and goes
-- through text_edits.guess instead. Here it applies to every source.
--
-- Two deviations from Zed:
--   * Zed compares `completion.label`; we compare `edit.newText`, the string
--     that is actually written. For snippets, or servers whose label differs
--     from the inserted text, Zed's test runs against the wrong string.
--   * Zed widens to the server's `replace_range.end`; we use blink's own
--     keyword scan, because `InsertReplaceEdit.replace` is discarded inside
--     `get_from_item` before we ever see the edit. The guard below makes that
--     safe: we only ever widen an edit that stopped at the cursor, so we can
--     never shrink or extend a range a server chose deliberately.
local M = {}

--- Patch blink's edit-range resolution. Idempotent: a `:Lazy reload` of
--- blink.cmp gives us a fresh module table, so re-running setup re-wraps the
--- fresh copy instead of stacking wrappers on a stale one.
function M.setup()
    local text_edits = require("blink.cmp.lib.text_edits")
    if text_edits.__box_replace_suffix then
        return
    end

    local context = require("blink.cmp.completion.trigger.context")
    local fuzzy = require("blink.cmp.fuzzy")
    local get_from_item = text_edits.get_from_item

    text_edits.get_from_item = function(item)
        local edit = get_from_item(item)
        local new_text, range = edit.newText, edit.range
        -- `newText` can be nil: guess() yields nil for an item with neither
        -- insertText nor label, and keyword.guess_keyword_range returns before
        -- it ever looks at the word when the keyword starts at column 0.
        if type(new_text) ~= "string" or new_text:find("\n", 1, true) then
            return edit
        end

        local cursor = context.get_cursor()
        local col = cursor[2]
        if
            -- only ever widen a single-line edit, and only on the cursor's line
            range["end"].line ~= range.start.line
            or range.start.line ~= cursor[1] - 1
            -- An edit that does not end exactly at the cursor was chosen to
            -- cover more (or less) than the text before it — a server's own
            -- replace range, or an inverted range after the cursor moved left.
            -- Leave those alone: this only turns a plain insert into a replace.
            or range["end"].character ~= col
        then
            return edit
        end

        -- blink's own keyword scan, so "the tail" means the same thing here as
        -- it does to the fuzzy matcher. The third argument is the string
        -- 'prefix'/'full': fuzzy.get_keyword_range normalises it with
        -- `range == 'full'` before handing the boolean to whichever
        -- implementation is active (fuzzy/init.lua:156).
        local line = context.get_line()
        local _, keyword_end = fuzzy.get_keyword_range(line, col, "full")
        local tail = line:sub(col + 1, keyword_end)
        if tail ~= "" and new_text:lower():sub(-#tail) == tail:lower() then
            range["end"].character = keyword_end
        end
        return edit
    end

    text_edits.__box_replace_suffix = true
end

return M