return {
    {
        "milanglacier/minuet-ai.nvim",
        enabled = not vim.g.is_rhel6,
        version = false,
        event = "InsertEnter",
        config = function()
            -- resolve the opencode zen key from opencode's own auth file
            -- (~/.local/share/opencode/auth.json, provider "opencode-go")
            -- instead of requiring a separate OPENCODE_GO_API_KEY env var;
            -- falls back to the env var when the auth file/field is absent
            local auth_file = vim.fs.joinpath(
                vim.fs.dirname(vim.fn.stdpath("data")),
                "opencode",
                "auth.json"
            )
            local function opencode_api_key()
                local f = io.open(auth_file, "r")
                if f then
                    local ok, auth = pcall(vim.json.decode, f:read("*a"))
                    f:close()
                    local key = ok and auth and auth["opencode-go"] and auth["opencode-go"].key or nil
                    if key and key ~= "" then return key end
                end
                return os.getenv("OPENCODE_GO_API_KEY") or ""
            end

            -- the /go endpoint requires a session header (401/InvalidRequest
            -- "MissingSessionID" otherwise); any stable identifier works
            local function add_opencode_session(data)
                data.headers["x-opencode-session"] = "nvim-minuet"
                return data
            end

            require("minuet").setup({
                -- Opencode Go backend (minuet README "Opencode Go" recipe, with
                -- the chat model set to glm-5.3-flash: fastest TTFT on the
                -- endpoint (~1.1s, measured with a ~850-token context); README's
                -- tuned recipe uses deepseek-v4-flash).
                provider = "openai_compatible",
                -- keep in sync with blink's minuet provider timeout_ms
                request_timeout = 2.5,
                -- slower cadence: fewer LLM calls, lower cost / rate-limit risk
                throttle = 1500,
                debounce = 600,
                -- chat default is 2: a 1-char typed prefix echoed by the model
                -- (typed `p`, suggestion `print()`) was never trimmed -> duplicated
                -- chars after accept in the blink menu AND virtual text.
                -- Trimming is concat-neutral (edge overlap removed from the
                -- candidate), so 1 is safe.
                before_cursor_filter_length = 1,
                -- minuet stays manual-only in the blink menu (<A-y>): letting
                -- the source auto-fire AND virtualtext auto-trigger would send
                -- two LLM requests per typing pause
                blink = { enable_auto_complete = false },
                provider_options = {
                    openai_compatible = {
                        api_key = opencode_api_key,
                        end_point = "https://opencode.ai/zen/go/v1/chat/completions",
                        model = "glm-5.3-flash",
                        name = "Opencode",
                        optional = {
                            max_tokens = 56,
                            top_p = 0.9,
                            -- disable thinking to avoid first-token latency
                            thinking = { type = "disabled" },
                        },
                        transform = { add_opencode_session },
                    },
                },
                virtualtext = {
                    -- OFF by default: minuet keeps the auto-trigger state in a
                    -- per-buffer flag (vim.b.minuet_virtual_text_auto_trigger),
                    -- NOT in this list -- so an empty list means "never
                    -- auto-armed"; <leader>ua arms it per buffer.
                    auto_trigger_ft = {},
                    -- prose / note buffers: no ghost text
                    auto_trigger_ignore_ft = { "org", "markdown", "text", "help", "gitcommit" },
                    keymap = {
                        -- README defaults (all free of existing <M-*> maps)
                        accept = "<A-A>",
                        accept_line = "<A-a>",
                        accept_n_lines = "<A-z>",
                        next = "<A-]>",
                        prev = "<A-[>",
                        dismiss = "<A-e>",
                    },
                },
                duet = {
                    -- separate provider from inline completion (docs: configured
                    -- the same way). Upstream currently recommends
                    -- gemini-3-flash-preview for NES quality; glm-5.3-flash is
                    -- untested for duet, revisit if predictions are poor.
                    provider = "openai_compatible",
                    provider_options = {
                        openai_compatible = {
                            api_key = opencode_api_key,
                            end_point = "https://opencode.ai/zen/go/v1/chat/completions",
                            model = "glm-5.3-flash",
                            name = "Opencode",
                            optional = {
                                -- no max_tokens here: duet returns the FULL
                                -- rewritten region; truncated output is rejected
                                thinking = { type = "disabled" },
                            },
                            transform = { add_opencode_session },
                        },
                    },
                },
            })

            local map = vim.keymap.set

            -- Master switch for both AI fronts, per buffer (minuet stores the
            -- state in vim.b.*_auto_trigger flags, so this is buffer-scoped).
            -- Both start OFF: duet auto_trigger_ft is empty by default and the
            -- virtual text list is empty above.
            local function ai_toggle()
                local on = not (vim.b.minuet_virtual_text_auto_trigger or vim.b.minuet_duet_auto_trigger)
                vim.b.minuet_virtual_text_auto_trigger = on or nil
                vim.b.minuet_duet_auto_trigger = on or nil
                vim.notify("Minuet AI (virtual text + duet): " .. (on and "ON" or "OFF"), vim.log.levels.INFO)
            end
            map("n", "<leader>ua", ai_toggle, { desc = "Toggle Minuet AI (ghost text + duet)" })

            -- duet keys live in the <leader>a family (Avante owns aa/ae/at)
            map("n", "<leader>ap", "<cmd>Minuet duet predict<cr>", { desc = "Duet predict (NES)" })
            map("n", "<leader>aA", "<cmd>Minuet duet apply<cr>", { desc = "Duet apply" })
            map("n", "<leader>ax", "<cmd>Minuet duet dismiss<cr>", { desc = "Duet dismiss" })
            map("n", "<leader>aT", "<cmd>Minuet duet toggle<cr>", { desc = "Duet auto toggle (buffer)" })
        end,
    },
}
