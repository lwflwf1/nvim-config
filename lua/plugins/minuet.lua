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
            -- opencode stores it under ~/.local/share/opencode on Windows too
            -- (verified: %LOCALAPPDATA%\opencode does not exist), so try the home
            -- path first, then the XDG dir next to stdpath("data").
            local auth_files = {
                vim.fs.joinpath(vim.fn.expand("~/.local/share/opencode"), "auth.json"),
                vim.fs.joinpath(vim.fs.dirname(vim.fn.stdpath("data")), "opencode", "auth.json"),
            }
            local function opencode_api_key()
                for _, auth_file in ipairs(auth_files) do
                    local f = io.open(auth_file, "r")
                    if f then
                        local ok, auth = pcall(vim.json.decode, f:read("*a"))
                        f:close()
                        local key = ok and auth and auth["opencode-go"] and auth["opencode-go"].key or nil
                        if key and key ~= "" then return key end
                    end
                end
                return os.getenv("OPENCODE_GO_API_KEY") or ""
            end

            -- the /go endpoint needs x-opencode-session (else MissingSessionID,
            -- mandatory since 2026-09-05), and that value is opencode's *backend
            -- affinity* key: requests sharing it stay pinned to one backend,
            -- which is what keeps the prompt cache warm. So it must not be a
            -- constant -- the old fixed value pinned every minuet user to one
            -- shared backend, interleaving our traffic with strangers' so the
            -- cache rarely hit. One opaque id per nvim run gives this instance
            -- exclusive affinity and is stable for the run; opencode treats the
            -- value as opaque (pi hardcodes "wsl"). %x, not tostring: hrtime is
            -- past 2^53 and tostring would render it as "1.29e+15". Minted here,
            -- not inside the transform, which sits on minuet's request path.
            local opencode_session = string.format("%x", vim.uv.hrtime())
            local function add_opencode_session(data)
                data.headers["x-opencode-session"] = opencode_session
                return data
            end

            require("minuet").setup({
                -- Opencode Go backend (minuet README "Opencode Go" recipe, with
                -- the chat model set to glm-5.3-flash: fastest TTFT on the
                -- endpoint (~1.1s, measured with a ~850-token context); README's
                -- tuned recipe uses deepseek-v4-flash).
                provider = "openai_compatible",
                -- --max-time for the whole request; through the local proxy
                -- glm-5.3-flash measured 1.4-5.0s to first token on this box,
                -- so a 2.5s budget returned nothing on most attempts
                -- keep in sync with blink's minuet provider timeout_ms
                request_timeout = 6,
                -- HTTP/2 through the local proxy stalls ~15s now and then
                -- (curl exits 000); pinning HTTP/1.1 avoids it
                curl_extra_args = { "--http1.1", "--connect-timeout", "5" },
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
                        accept_line = "<A-a>", -- one line only (JetBrains' End)
                        next = "<A-]>", -- VSCode Alt+] - cycle candidates
                        prev = "<A-[>",
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

            map("n", "<leader>aD", "<cmd>Minuet duet toggle<cr>", { desc = "Duet auto toggle (buffer)" })
        end,
    },
}
