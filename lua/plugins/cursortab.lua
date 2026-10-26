-- cursortab owns BOTH AI fronts now: inline ghost text AND next-edit
-- prediction (NES). It replaced milanglacier/minuet-ai.nvim, which was two
-- separate things on one remote chat endpoint (virtualtext + blink source, and
-- `duet` for NES) -- see AGENTS.md for why that arrangement could not survive
-- going local: minuet's duet targets general-purpose LLMs, and upstream says so
-- ("It only targets general-purpose LLMs rather than NES-specialized models").
--
-- The model is a LOCAL llama.cpp server, started outside nvim (see
-- AGENTS.md "Local AI model"); nothing here spawns it. The daemon, however, IS
-- spawned by setup() and outlives the editor.
return {
    {
        "cursortab/cursortab.nvim",
        -- RHEL6: no Go toolchain offline (go.mod wants 1.25), and a
        -- darwin/arm64 daemon binary sitting in data/lazy/ is dead weight
        -- there. lazy's fix_disabled() (core/meta.lua:305) deletes or disables
        -- the spec, so neither `build` nor setup() ever runs there.
        enabled = not vim.g.is_rhel6,
        -- NOT pinned to a tag. The newest tag (v0.8.0) hard-errors on
        -- `provider.type = "zeta-2.1"`: config.lua:321 validates against a
        -- literal list (inline, fim, sweep, zeta-2, zeta, copilot,
        -- mercuryapi) and `error()`s, which takes the whole config down with
        -- it. zeta-2.1 -- and windsurf -- are main-only, while the README
        -- documents main. Same shape as the opencode.nvim trap in AGENTS.md,
        -- inverted: there `*` ran ahead of the tags, here the tags lag behind
        -- what the README promises. Hence `version = false` (track main).
        version = false,
        -- The daemon is spawned by setup() and survives nvim exiting, so there
        -- is nothing to defer; `lazy = false` is also what lets `init` below run
        -- before setup() and catch the first state event.
        lazy = false,
        build = "cd server && go build",
        -- The <Tab>/<Esc> chains in plugins/editing.lua need a `condition` to
        -- test, and cursortab has no public is_visible(). mini.keymap REJECTS a
        -- step table whose condition is not callable (keymap.lua:657
        -- normalize_steps), so a bare "call accept() and fall through on
        -- false" step is not an option. Track the engine state instead --
        -- `CursortabStateChanged` is documented, and on_state_change fires once
        -- on connect, so this must subscribe in `init` (before setup()), not in
        -- config(), or the first status is missed.
        init = function()
            -- The WHOLE payload is recorded, not just `.state`. Reading
            -- `args.data.state` blind looked fine (a headless probe fired the
            -- autocmd by hand and the variable tracked it) but pinned the value
            -- at "Idle" for every real session: a Go RPC struct's field names do
            -- not survive the hop in a shape you can rely on, and a nil there
            -- silently took the `or "Idle"` fallback forever. `:echo
            -- g:cursortab_status` dumps the raw table; the chain's condition
            -- derives the state from it with fallbacks rather than trusting one
            -- key.
            vim.g.cursortab_status = {}
            vim.api.nvim_create_autocmd("User", {
                pattern = "CursortabStateChanged",
                callback = function(args)
                    local st = type(args.data) == "table" and args.data or {}
                    -- the daemon re-broadcasts on every request, so most of these
                    -- carry the same state; only a real transition is worth a
                    -- statusline redraw
                    if st.state == vim.g.cursortab_status.state then return end
                    vim.g.cursortab_status = st
                    -- lualine is VeryLazy, so it may not be loaded yet on the
                    -- first event (which lands right at connect)
                    pcall(function()
                        require("lualine").refresh({})
                    end)
                end,
            })
        end,
        config = function()
            require("cursortab").setup({
                -- The documented blink integration (README "blink.cmp").
                -- `ghost_text = false` moves the single-line end-of-line text
                -- out of cursortab's own overlay and into the blink menu, so it
                -- competes with lsp/lazydev/buffer instead of being a separate
                -- visual channel. Multi-line edits and the cursor-prediction UI
                -- still render natively -- blink's source only consumes
                -- `append_chars`, so the AI UI does now live in two places.
                blink = { enabled = true, ghost_text = false },

                -- Both keys have to be given up. Insert <Tab>/<S-Tab> belong to
                -- the tab-out engine's chains (editing.lua), and normal <Tab>
                -- must still fall through to the raw key (<C-i>, jumplist
                -- forward). Accept is driven from those chains through the
                -- public accept() instead. partial_accept has no Lua entry
                -- point at all, and its default <S-Tab> would shadow the
                -- blink_prev / back-in / dedent chain.
                keymaps = {
                    accept = false,
                    partial_accept = false,
                    -- Manual trigger, and the ONLY way past the gating:
                    -- `Engine.suppressCompletionRequest` returns "" immediately
                    -- when `manual` is true (server/engine/request.go:74), so
                    -- every suppression is skipped -- "no recent edits" (i.e.
                    -- `!IsModified()`, suppress.go:99, an UNMODIFIED buffer),
                    -- disabled treesitter scope, mid-line, single deletion.
                    -- That makes it the probe for "does the model actually
                    -- produce something", independent of where the cursor is.
                    -- <A-y> was minuet's manual-AI-completion key and is free
                    -- again now that minuet is gone.
                    trigger = "<A-y>",
                },

                provider = {
                    -- `sweep` while we compare latency. Upstream's own 50-scenario
                    -- benchmark (README) says all three local next-edit models
                    -- trade the same way: sweep is ~10x faster to first token but
                    -- its QUIET RATE is 36% vs zeta-2.1's 100% -- i.e. sweep
                    -- fires on 64% of the scenarios where it should stay quiet,
                    -- which is what decides whether a front is usable day to day.
                    -- So this is a latency experiment, not a conclusion.
                    --   sweep-1.5B  score 0.21  deltaChrF 43.7  show 68%  quiet 36%  p50  157ms
                    --   zeta-2.1    score 0.57  deltaChrF 60.6  show 88%  quiet 100% p50 1504ms
                    --   zeta-2      score 0.61  deltaChrF 65.4  show 92%  quiet  96% p50  551ms
                    -- zeta-2 (not 2.1) is the one to try next: better score than
                    -- 2.1 AND ~2.7x lower p50, which is the symptom we actually
                    -- have (zeta-2.1 measured p50 5.1s on this M4).
                    --
                    -- Kept from the zeta-2.1 run, because the comparison is only
                    -- meaningful if the request budget is held fixed -- the whole
                    -- latency difference has to come from the model.
                    type = "sweep",
                    url = "http://localhost:8000",
                    -- model left unset: llama-server serves one model and
                    -- reports it on /v1/models, so there is nothing to keep in
                    -- sync here.
                    temperature = 0.0,
                    -- These three are ONE arithmetic problem, not three knobs.
                    -- The box decodes at ~20 tok/s (measured, see AGENTS.md), so
                    -- max_tokens IS the request's wall-clock ceiling:
                    --   256 tok = 12.8s -> fits completion_timeout with ~1.5x
                    --     headroom, and a diff payload is tens of tokens, so
                    --     this is generous rather than tuned
                    --   512 tok = 25.6s -> exceeds completion_timeout and the
                    --     daemon reports `context deadline exceeded`
                    -- context_size 2048 keeps the prompt (~1200 tok measured) well
                    -- inside the prefill budget; 4096 only makes every request
                    -- slower for no gain.
                    -- Raise completion_timeout ONLY if these two stop agreeing.
                    max_tokens = 256,
                    context_size = 2048,
                    -- Wall-clock budget, and it has to stay above
                    -- max_tokens / decode rate with room for the p90 tail. At
                    -- ~20 tok/s, 256 tokens is 12.8s, so 12s was too tight and
                    -- 20s gives ~1.5x headroom. blink's provider timeout_ms MUST
                    -- match this value (see plugins/blink.lua).
                    completion_timeout = 20000,
                    privacy_mode = true,
                },

                behavior = {
                    -- Both trigger paths, raised from the 50ms defaults. The
                    -- reasoning is not "the model is slow" (that is
                    -- completion_timeout's job) but QUEUEING: at a 5s latency
                    -- a 400ms cadence means ~12 requests are in flight per
                    -- prediction cycle, and the server log showed 2631 queue
                    -- events against 608 completed generations -- most of that
                    -- work is stale by the time it lands. Matching the cadence
                    -- to roughly the latency keeps one prediction in flight.
                    --
                    -- It also matters for NES specifically: next-edit prediction
                    -- needs accumulated edit history to know that a rename here
                    -- means "fix the call sites there", and a 400ms cadence
                    -- gives each request almost none.
                    idle_completion_delay = 1500,
                    text_change_debounce = 1500,
                    -- LEFT AT UPSTREAM'S DEFAULT ({}), deliberately.
                    -- `disabled_in = { "comment", "string" }` is the obvious
                    -- thing to add and it is WRONG here: the daemon enforces it
                    -- as `suppressForDisabledScope` (server/engine/suppress.go),
                    -- i.e. it DROPS THE REQUEST rather than trimming the
                    -- prediction, and the treesitter scope lookup fires far more
                    -- eagerly than "the cursor sits inside a comment". With it
                    -- set, the daemon log filled with
                    -- `suppressed: disabled treesitter scope` while the server
                    -- received no requests at all.
                    disabled_in = {},
                    cursor_prediction = {
                        enabled = true,
                        auto_advance = true,
                        -- min line distance before a jump indicator is drawn;
                        -- 2 keeps same-line and adjacent-line predictions from
                        -- flickering
                        proximity_threshold = 2,
                    },
                    -- Knob, deliberately not set: local models are weak on HDL,
                    -- so if NES turns out to be noise on .sv,
                    -- ignore_filetypes = { "systemverilog", "verilog" } is the
                    -- dial. Measure before deciding.
                },

                -- no anonymous usage data (opt-in upstream)
                contribute_data = false,
                -- "debug" while this is still being brought up. The gating
                -- decisions (`suppressed: no recent edits` / `disabled treesitter
                -- scope` / `mid-line` / `single-deletion`) and the fim truncation
                -- notice are ALL debug-level, so "info" makes a silent front
                -- indistinguishable from a broken one -- which is exactly the
                -- trap that cost a round here. Drop it once it is boring.
                log_level = "debug",
            })

            -- Replaces minuet's per-buffer <leader>ua. Note this one is a
            -- daemon-wide on/off (:CursortabToggle), not per-buffer: cursortab
            -- keeps no per-buffer auto-trigger state to arm.
            vim.keymap.set("n", "<leader>ua", "<cmd>CursortabToggle<cr>", {
                desc = "Toggle cursortab (ghost text + NES)",
            })
        end,
    },
}
