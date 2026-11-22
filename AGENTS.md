# AGENTS.md — lwflwf1/nvim-config

Guidance for AI agents and humans working in this Neovim configuration repo.

## What this is

A personal Neovim config (lazy.nvim based) maintained for **two targets**:

1. **Windows** (primary dev machine) — `C:\Users\yingfangong\AppData\Local\nvim`
2. **RHEL6 offline intranet machine** (kernel 2.6.32 / glibc 2.17) — deployed from a
   self-contained bundle, no network.

The same repo drives both; platform differences are gated by `vim.g.os`
(`"windows" | "linux" | "macos"`) and `vim.g.is_rhel6` (set in `init.lua`).

- Remote: `git@github.com:lwflwf1/nvim-config.git` (branch `master`).
- Normal workflow: edit locally on Windows, commit + push, then **package** and
  ship to RHEL6 (see "Packaging" below).

## Repository layout

```
init.lua                  entry point: platform detect, lazy bootstrap, module requires
ginit.vim                 GUI (Neovide) settings
lazy-lock.json            plugin lockfile (committed; pins every plugin)
lua/
  core/                   options.lua, keymaps.lua, autocmds.lua   (block 1: plain vim config)
  plugins/                one file per plugin (lazy spec) — THE import dir (block 2)
  box/                    the personal module (block 3, mini/snacks style). init.lua
                          has setup() (early: keymaps/autocmds/commands) and
                          setup_late() (after lazy: theme/lsp/tools). Submodules:
                          project (root/auto-cwd/pin, <leader>p*), sos (SOS +
                          generators, <leader>s*), sessions (mini.sessions helpers,
                          shared by editing keymaps + lualine), toggle_value (<leader>sw), trim
                          (<leader>ue), wins, multicursor, smart_gf, winpick, lsp, parsers,
                          terminals (<leader>fe / :Terminals picker over snacks terminals),
                          theme (+<leader>uC), colors (blade2049: the 2049 palette +
                          its role overrides), hl (groups the colorschemes don't
                          define), picker_hl (snacks picker window bg patch),
                          tools (:ToolInstall), neovide, battery,
                          fff_picker (snacks patch), notifier_anim (snacks patch),
                          anim (generic window animation framework: core.lua +
                          slide/fade/spring effects; notifier_anim configures it),
                          blink_suffix (blink.cmp patch, Zed-style replace_suffix),
                          tabout (TabOut-rules engine for the smart multistep
                          Tab/S-Tab; chains declared in plugins/editing.lua),
                          sticky (WIP), wakatime (:WakaExport/:WakaSync)
  async.lua               compat shim: async.lua -> promise-async -> async.nvim
  snippets/               LuaSnip snippets
after/
  ftplugin/               per-filetype overrides (systemverilog, log, markdown, ralf, tc, bigfile)
  queries/systemverilog/  context.scm
  syntax/                 ralf.vim, tc.vim
queries/systemverilog/    aerial, function_*, variables (the rest come from the SV fork)
colors/                   catppuccin-blade2049.lua: the `:colorscheme` entry point.
                          Snacks' colorschemes picker enumerates exactly this dir,
                          so without the shim the flavour is unreachable AND
                          box/theme.lua has no colors_name to persist.
lua/catppuccin/palettes/  blade2049.lua: a ONE-LINE adapter to
                          box/colors/blade2049.lua -- catppuccin resolves a
                          flavour's palette by filename, so the file must exist
                          (see the blade2049 bullet for why an adapter and not
                          `color_overrides`).
scripts/                  installers + packagers + tools.json
  build-fff-rhel6.sh      cross-build fff's backend for glibc 2.17 (run on Linux/WSL)
  wakatime-export.sh      RHEL6: dump the queue, pack+mail it via ferry (see below)
  prebuilt/fff/           GENERATED (gitignored): RHEL6 libfff_nvim.so, built by build-fff-rhel6.sh
.opencode-memory/         local agent session memory (gitignored)
```

## Startup flow (`init.lua`)

1. Set `vim.g.os` from `vim.uv.os_uname()`; on Linux compute `vim.g.is_rhel6`
   (kernel `2.6.32` or glibc `< 2.18`) and `vim.g.glibc_version`.
2. Windows: set clipboard to `win32yank`, set proxy env (`127.0.0.1:7897`), extend PATH.
3. Neovim core: `require("core.options")`, `core.keymaps`, `core.autocmds`.
4. `require("box").setup()` — personal module, early phase (keymaps/autocmds/commands).
5. Bootstrap `lazy.nvim` (clones if missing) and `require("lazy").setup({ spec = { { import = "plugins" } } })`.
6. `require("box").setup_late()` — theme/LSP/tools, once plugins are on the rtp.

**Architecture (3 blocks):** (1) `core/` = plain vim config; (2) `plugins/` = lazy specs;
(3) `box/` = everything custom (features, plugin patches, misc). Specs may
`require("box.*")` (patch nature); `core/` must stay dependency-free.

**Important:** `lazy.setup` uses `spec = { import = "plugins" }` — every Lua file
under `lua/plugins/` is treated as a lazy plugin spec. Files at `lua/` root
(e.g. `async.lua`) are NOT plugin specs.

## Conventions

- **Leader** = `<Space>` (`core/keymaps.lua`).
- Each plugin = one file in `lua/plugins/`, returning a lazy spec table.
- Prefer `opts = {}` over `config = function()` when the plugin follows the
  lazy.nvim convention; use `config` only when extra wiring is needed.
- Use `vim.tbl_extend`/`vim.tbl_deep_extend` and guard optional plugin loads with
  `pcall(require, ...)`.
- Keep comments concise and explain *why* (non-obvious decisions), not *what*.
- LuaLS is configured with `diagnostics.globals = { "vim", "Snacks" }`
  (`box/lsp.lua`); keep `lua_ls` clean (`lua-language-server --check`, see below).

## Non-obvious design decisions (do not "fix" without reading the comment)

- **RHEL6 guards:** `vim.g.is_rhel6` disables avante, cursortab, snacks.scroll, and
  forces blink.cmp's fuzzy to the pure-Lua implementation (the prebuilt Rust fuzzy
  lib needs glibc ≥ 2.18). **RHEL6 nvim is kept on the same version as Windows
  (both 0.13-dev)** — do NOT add version-branch shims for "older nvim"; only branch
  on `is_rhel6` for real glibc/tooling matters. (yazi.nvim is **not** `is_rhel6`-gated
  anymore — see the yazi bullet below.)
- **The RHEL6 gate is glibc linkage, NOT the kernel version.** Measured on the real
  box: fzf (Go, static), **wakatime-cli v2.27.1 (Go 1.27.2, static)** and yazi (Rust,
  musl static-pie) all run fine on kernel **2.6.32**; fff and blink's fuzzy lib fail
  purely because they are **dynamically linked against glibc ≥ 2.18 / 2.31**. Go's
  "kernel ≥ 3.2 since go1.24" line (go.dev/wiki/MinimumRequirements) is a *supported
  baseline*, not something the runtime checks — the one documented hard crash is
  `runtime.procresize: invalid arg` on CentOS 6 (golang/go#77374). So: `file <bin>`
  showing `statically linked` ⇒ stop worrying about the kernel; `ldd` showing
  `libc.so.6` ⇒ check its GLIBC_ versions instead. **Do not pre-judge a static binary
  as unrunnable on RHEL6 — test it** (one `--version` run answers it).
- **cursortab.nvim is the AI front** (`plugins/cursortab.lua`), for BOTH inline
  ghost text and next-edit prediction (NES), against a **local** llama.cpp
  server. It replaced `milanglacier/minuet-ai.nvim`; do not re-introduce minuet
  for this. Two independent reasons, both verified upstream:
  - minuet's `duet` (its NES) is chat-model only. Its README: *"It only targets
    general-purpose LLMs rather than NES-specialized models, as I lack local GPU
    resources for testing"*, and it names `claude-haiku-4.5` / `gpt-5.4-mini` as
    already performing poorly — i.e. the tier **below** what a 16 GB machine can
    serve locally. There is no small local config where duet is usable.
  - cursortab is the only one of the candidates that implements the actual NES
    affordance: `behavior.cursor_prediction` (jump pill, `auto_advance`,
    off-screen direction arrow + line distance). `blink-edit.nvim` renders
    ghost text and `<Tab>`-accepts a hunk but has **no jump indicator at all**,
    so it is not NES. It is also unmaintained (last push 2026-02-01) and has no
    gating. Gating is what decides whether an NES front is usable: cursortab
    publishes the only benchmark, and its *quiet rate* (fires when it should not)
    separates the field — zeta-2 96%, sweep-1.5B **36%**.
  - **`version = false`, i.e. track `main`, NOT a tag.** The newest tag (v0.8.0)
    hard-`error()`s on `provider.type = "zeta-2.1"`: `config.lua:321` validates
    against a literal allow-list (`inline, fim, sweep, zeta-2, zeta, copilot,
    mercuryapi`) and throws, which aborts the whole `setup()` — so a pinned tag
    silently leaves the *defaults* in place (`inline`, `accept = "<Tab>"`),
    which then fights the tab-out chain. `zeta-2.1` (and `windsurf`) are
    main-only while the README documents main. This is the opencode.nvim trap
    below, inverted: there `*` ran ahead of the tags, here the tags lag behind
    what the README promises. `sweepapi` also vanished between v0.7.8 and
    v0.8.0, so the tags are not strictly additive — main is simply ahead.
  - **`keymaps = { accept = false, partial_accept = false }` is load-bearing.**
    Insert `<Tab>`/`<S-Tab>` belong to the tab-out chains (`editing.lua`) and
    normal `<Tab>` must fall through to the raw key (`<C-i>`); cursortab's
    defaults would own all three. Accept is driven from those chains through the
    public `require("cursortab").accept()` (returns a boolean). There is **no
    public dismiss()** — `on_reject()` is the daemon's RPC callback for exactly
    this (clear the awaiting flag + close overlays), so calling it is what the
    daemon itself would do on a rejection; it is an internal, guard it with
    `pcall`. `partial_accept` has no Lua entry point at all, which is why it
    cannot be re-wired and stays off.
- **The chains need a `condition`, so the state is tracked by hand.**
  `mini.keymap` *rejects* a step table whose `condition` is not callable
  (`keymap.lua:657` `normalize_steps` errors), so "just call `accept()` and
  return `false`" is not a step. cursortab has no `is_visible()` either. So
  `plugins/cursortab.lua`'s **`init`** hook subscribes to the documented
  `User CursortabStateChanged` and records the **whole payload** in
  `vim.g.cursortab_status`; the chain asks whether any of
  `HasCompletion | HasCursorTarget | StreamingCompletion` appears in it.
  Three details, all learned the hard way:
  - it must be `init`, not `config`, because `on_state_change` fires once
    on connect and a `config()`-time autocmd misses it;
  - **do not read `args.data.state` and nothing else.** A Go RPC table's
    field names are not a contract we control, and a nil there took the
    `or "Idle"` fallback forever: the chains' condition sat at `Idle` while
    the server log showed hundreds of completed generations. A headless probe
    CANNOT catch this — firing the autocmd by hand supplies a hand-made
    table with the documented shape. Hence record the payload and let the
    condition scan it, instead of trusting one key;
  - the tracked value is only the *condition*. It is written from a
    `vim.schedule`d RPC callback, so it lags a tick; `accept()`'s own
    return value is what decides whether the chain continues.
  - **`blink = { enabled = false }`.** Its blink source only consumes
    `append_chars` (single-line end-of-line ghost text); multi-line edits,
    replacements, deletions and the prediction UI always render through its own
    overlay. Enabling it would split the AI UI across two places for no gain,
    and blink's `sources.default` has no AI entry at all now.
  - **`enabled = not vim.g.is_rhel6` is sufficient, not aspirational.** lazy's
    `fix_disabled()` (`core/meta.lua:305`) deletes or disables the spec, so
    neither `build` nor `setup()` runs there — the Go requirement is a non-issue
    offline. The residual cost is packaging: `cd server && go build` produces an
    **extensionless** ~11 MB binary (`server/cursortab`) that `package.ps1` does
    NOT strip (it strips `*.dll/exe/cmd/bat`), so it rides along to RHEL6 as dead
    weight — same class as the yazi note below.
  - **`lazy = false` + a Go toolchain (go.mod wants 1.25).** `setup()` spawns a
    background daemon that **outlives nvim** (unix socket + pid + log in
    `stdpath("state")/cursortab/`), and it is reused across sessions. Probe
    gotcha: the daemon inherits nvim's stdio, so `timeout 60 nvim --headless ...`
    hangs *after* nvim has already exited. Read `stdpath()` with `nvim --clean`,
    or make the probe quit itself with an internal `vim.defer_fn(qa!)` failsafe.
  - **The model is not managed by nvim.** See "Local AI model" below; nothing in
    the config starts or downloads it. `<leader>ua` is now `:CursortabToggle` and
    is a **daemon-wide** on/off, not per-buffer like minuet's was (cursortab keeps
    no per-buffer auto-trigger state to arm).
- **opencode.nvim** (`plugins/opencode.lua`, replaced sidekick.nvim which only
  wrapped the opencode TUI in a terminal — and its NES was off). It drives the
  *installed* opencode CLI, so it is gated off on RHEL6 like cursortab/avante.
  Note it is NOT an NES front: that is cursortab's job now (above).
  - **Pinned to the 1.x tags (`version = "~1"`), on purpose.** Upstream's README
    states the split: the default branch is the OpenCode **v2** line, the tags
    are **v1**. This box stays on CLI v1 (1.19.0) because v2 is beta with
    reported V1→V2 session-history loss — so the plugin must follow v1 too.
  - **`"*"` is NOT "latest tag"** — it resolved to `main`'s tip (8 commits past
    v1.0.2), i.e. the v2 line. Use `~1`, which tracks the newest 1.x tag and can
    never select a v2 tag.
  - **`version` must be a string.** The upstream README suggests
    `vim.version.range("*")`; that returns a *table* and lazy dies in
    `manage/semver.lua:138` (`spec:find`) — it is not a lazy version spec.
  - **Config goes in `init`, not `opts`.** The plugin has no `setup()`; lazy
    silently drops `opts` for such specs, and the plugin reads `vim.g.opencode_opts`
    instead (same trap class as the wakatime bullet above).
  - **`server.url` is pinned per nvim instance, and that is load-bearing.**
    A free port is allocated lazily (`uv.new_tcp`, bind port 0) and threaded
    into both `start`'s `opencode --port <n>` and the URL. Do NOT drop the URL
    and rely on discovery: `discovery.find()` falls through to `locally()`,
    which adopts ANY local `opencode --port` whose cwd overlaps, so a second
    nvim in the same project silently talks to the first one's opencode
    (verified: it connected to a `serve` in the same cwd). `configured()` is
    checked before `locally()`, which is what the pin exploits. Consequences:
    a manually started `opencode` is no longer auto-adopted, and `select()`'s
    "server.connect" errors while the pinned server is down (`select.lua` chains
    `configured()` with no catch). That cannot be fixed from the config,
    because `find()` *needs* `configured()` to reject in order to trigger
    `server.start`.
  - **Only `server.url`/`server.start` are overridden** (snacks terminal instead
    of the default bare `vsplit term://opencode`, and the toggle key reuses
    `server_cmd()` so it finds the same terminal). `ask()`/`select()` need no
    config: the plugin auto-detects snacks by itself
    (`snacks.config.get("input",{}).enabled`), both of which
    `plugins/snacks.lua` already enables.
  - **lazy does not reconcile an already-installed plugin when the lockfile
    changes** — it only checks out on install/update. After editing the pin the
    worktree stayed on `main`, so it had to be `git checkout <locked-commit>`d by
    hand. Remember this when bumping the version.
  - Requires `opencode` >= 1.17 in `$PATH` (1.19.0 here); `:checkhealth opencode`
    reports version, curl, and snacks status.
- **AI request pacing** (`plugins/cursortab.lua`): every number below is
  MEASURED on the macOS box (M4 / 16 GB / zeta-2.1 Q4_K_M), not estimated.
  - **Latency is decode, not prefill.** One request = 4.4–7.7 s
    (p50 5.1 s, p90 7.7 s). The split: p50 generation is 79 tokens ×
    50 ms/token = 3.9 s, and that *is* the eval time (p50 3.8 s). The prompt
    (`n_past` p50 262, p90 700, max 893) is nearly free because
    `--cache-reuse 256` hits the entire prefix every request (the log's
    `after context reuse, new n_past = X` comes back unchanged). So the knob
    that moves latency is the model's tok/s, not the context size.
  - **`completion_timeout = 12000`** (was 8000, which produced two real
    `context deadline exceeded` errors against a 7.7 s p90). Raising it stops
    the tail from erroring; it does not make anything faster.
  - **`idle_completion_delay` / `text_change_debounce` = 1500** (default 50).
    The reason is queueing, not politeness: at a 5 s latency a 400 ms cadence
    leaves ~12 requests in flight per prediction cycle — the server log showed
    **2631 queue events against 608 completed generations**, so most of that
    work is stale before it lands. Matching cadence to latency keeps roughly
    one prediction in flight. It also gates NES specifically: next-edit
    prediction needs accumulated edit history to know a rename here means
    "fix the call sites there", and a 400 ms cadence gives each request none.
- **Completing mid-identifier** (`lua/box/blink_suffix.lua`, wired from
  `plugins/blink.lua`): blink's `completion.keyword.range` has only `'prefix'`
  (edit stops at the cursor) and `'full'` (edit always runs to the end of the
  keyword). `'prefix'` duplicates the text already after the cursor —
  `creat|eProject()` + `createProject` → `creat`eProject… → `createProjecteProject()`.
  **`'full'` is not the fix**: it eats unrelated tails, because `-` is a keyword
  character in *both* fuzzy implementations (`[\p{L}0-9_-]` in
  `fuzzy/rust/keyword.rs:7-8`, iskeyword `@,48-57,_,-,192-255` in
  `fuzzy/lua/keyword.lua:14`), so `foo-|bar` loses `bar`; blink #968 also reported
  the cursor jumping to line 1 with `'full'`. So the patch wraps
  `blink.cmp.lib.text_edits.get_from_item` — the one place blink turns a
  CompletionItem into an edit range, and the one *every* caller goes through
  (cmp/init.lua ghost text + accept, cmp/preview.lua, cmp/libs/luasnip.lua,
  cmp/libs/vsnip.lua) — and widens the range **only when the tail really is a
  suffix of the candidate** (case-insensitive, length-aware). That is Zed's
  `completions.lsp_insert_mode = "replace_suffix"` test
  (`crates/editor/src/editor.rs:11712-11806`); upstream has no equivalent
  (saghen/blink.cmp#1767, #657). Notes:
  - It covers **every** source, LSP or not, which is the whole point: Zed only
    tests completions carrying an `InsertReplaceEdit`, so Zed itself would not fix
    a `buffer`/`lazydev` item, which has no `textEdit` and goes through
    `text_edits.guess`. This is Zed's idea, not a port.
  - It compares `edit.newText`, not Zed's `completion.label` — for snippets, or
    servers whose label differs from the inserted text, Zed tests the wrong string.
  - It widens to blink's own keyword scan, not the server's `replace_range.end`,
    because `InsertReplaceEdit.replace` is discarded inside `get_from_item`
    (`text_edits.lua:155-156`) before any wrapper can see it.
  - Mutating the returned edit in place is safe: it is always a fresh table
    (`deepcopy` for the `textEdit` path, a table literal for `guess`), and blink
    itself mutates it in 3 of the 5 paths. `luasnip`/`brackets` only read
    `range.start`, so widening is a no-op there. It also *improves*
    `accept.dot_repeat`, which derives `chars_to_delete` from `end.character` —
    without the widening `.` would re-insert and leave the tail behind.
  - **Do NOT set `keyword.range`** to fix duplication. It also feeds
    `match_suffix` (`blink/cmp/fuzzy/init.lua:130`), so `'full'` changes which
    candidates are *offered*, not merely what gets edited. The patch needs
    `'prefix'` as its baseline and only ever widens an edit that stopped at the
    cursor, so it can never shrink or extend a range a server chose deliberately.
  - `fuzzy.get_keyword_range(line, col, range)`'s third argument is the **string**
    `'prefix'`/`'full'`; the dispatcher normalises it with `range == 'full'` before
    handing the boolean to whichever implementation is active
    (`fuzzy/init.lua:156-158`). Passing a boolean is silently wrong (it compares
    `true == 'full'` → false) and looks like an upstream inconsistency if you
    forget the normaliser exists.
- **Explorer fuzzy** (`plugins/snacks.lua`): upstream sets
  `matcher = { sort_empty = false, fuzzy = false }` for the tree
  (`snacks/picker/config/sources.lua`, `M.explorer`), so fuzzy is enabled here.
  Sorting stays the explorer's own `sort` field and only reorders *within* a
  directory — in a tree the useful half of fuzzy is filtering, not ordering.
  **`<a-r>` / `toggle_regex` is a no-op for this source**: it writes
  `picker.opts.regex` (`snacks/picker/config/init.lua:100`) while the matcher
  reads a **deep copy** of `picker.opts.matcher` (`snacks/picker/core/picker.lua:112`
  → `core/matcher.lua:53`, `tbl_deep_extend` makes a new table); `opts.regex` is
  only read by the *grep* source, to decide about `--fixed-strings`
  (`grep.lua:58`). With fuzzy on, `^foo`, `foo$`, `!foo`, `'foo'` and `a | b` all
  still work — `_prepare` turns fuzzy off **per token**
  (`core/matcher.lua:268-333`) — but the anchor is the **displayed relative
  path**, not the basename (`^uart` does not match `src/driver/uart_ctrl.sv`).
  Regex is also a *global* opt, so enabling it would reinterpret `^foo$` as real
  regex anchors and break that per-token syntax — which is the other reason it is
  left off.
- **yazi on RHEL6** (`plugins/yazi.lua`): the plugin enables wherever
  `vim.fn.executable("yazi") == 1` (no `is_rhel6` check). The upstream **musl
  static-pie** build (`yazi-*-unknown-linux-musl.zip`) runs on the RHEL6 2.6.32
  kernel — verified on the real machine (2026-10); install it manually to
  `~/.local/bin` (`yazi`, optional `ya`), no glibc/patchelf involved. Do NOT use
  the GNU build: it needs glibc ≥ 2.39 (verified: fails on a 2.35 loader with
  `GLIBC_2.39`/`GLIBC_ABI_DT_RELR` not found). Caveat: the musl build sits below
  musl's 2.6.39 / Rust std's 3.2 official baselines — after bumping yazi,
  re-scan for post-2.6.32 syscalls (`mov eax,imm; syscall` pattern) before trusting it.
- **Auto cwd:** the only auto-cwd is the global `chdir` in `lua/box/project.lua`
  (the old window-local `lcd` in the former config/project.lua was removed, so all
  windows share one cwd that follows the current buffer's project). `<leader>pa`
  toggles it (`project.auto_enabled()`); `<leader>pp` prompts for a manual root
  (input + fd-backed picker, `--max-depth 3 --follow`, over that directory's
  subdirs; also the lualine cwd left-click), pins that root, chdir's
  there, and turns auto off.
  `box/fff_picker.lua` uses `project.get_root(0)` (pin when set, else the detected root) as the fff root / project gate.
- **FFF engine** (`plugins/fff.lua` + `box/fff_picker.lua`): `ff/fz/fw/fn/fo` are
  snacks.picker sources backed by fff's Rust index (programmatic API), **but only
  inside a project** (`project.get_root(0) ~= nil`); outside one they fall back to
  snacks' native `files`/`grep` (the `pick_*` dispatchers in `box/fff_picker.lua`; `fw`'s
  native fallback is `grep` seeded with the word — regex+live, to match the fff
  path — so it differs from `pw`'s `grep_word`). `vim.g.fff_mode = "off"` disables
  fff everywhere. There is deliberately no "always fff" mode — with no project it
  would index a possibly-giant cwd (e.g. `$HOME`, `C:\`). `pf/pg/pW` (the picked-root
  pickers) are always native. The root is captured per pick into `opts.fff_root` (survives finder
  retries and `:resume`) so a mid-pick project switch can't re-root the index out
  from under the finder. `fff.nvim` is a **single-global-root** index (no multi-root
  support) — `change_indexing_directory` re-roots by replacing + rescanning. RHEL6
  project trees live behind symlinks → `follow_symlinks = true`.
  - **The index starts at the first pick, never at startup** (`opts.lazy_sync =
    true` in `plugins/fff.lua`), plus a "never re-root mid-scan" guard in
    `fff_root_ready`. The plugin's own UIEnter hook roots the index at the CWD,
    i.e. wherever nvim was launched (often `$HOME`); on this box that scan ran for
    minutes (content-indexing the model files). And **any re-root while a scan is
    in flight wedges fff**: its reinit replaces the picker underneath the running
    scan, so the new picker keeps `is_scanning = true` and EVERY search returns 0
    until nvim restarts (reproduced; `scan_files()` and a second re-root do NOT
    heal it). With `lazy_sync` the first scan happens at the first pick, when
    auto-cwd has already chdir'd to the project; the guard makes the finder poll
    (350ms) instead of re-rooting while `is_scanning`, so switching projects
    during a scan delays results rather than killing fff. Accepted cost: fff's
    frecency `BufEnter` tracking is installed by `ensure_initialized`, so files
    opened before the first pick are not tracked.
- **fff is never used on RHEL6** (`init.lua` + `plugins/fff.lua` + `box/fff_picker.lua`):
  fff's search API is a *synchronous* FFI call (`live_grep`/`file_search` are mlua C
  functions bound to the Lua state), so it **cannot be made async** — it must run on
  the main loop (no `uv.new_thread`/`queue_work`, no callback API). On the big NFS
  project trees that both froze the UI and silently dropped matches (a
  `class.*packet` search missed a line a literal search found; fff's
  `grep.time_budget_ms`, default 150ms and counted *after the first match*, stops the
  scan wherever it runs out — and raising it to 400 only papered over it). So:
  - `init.lua` sets `vim.g.fff_mode = vim.g.is_rhel6 and "off" or "on"`; the single
    dispatch gate `fff_root_enabled()` (`box/fff_picker.lua`) then makes `ff/fz/fw/fn/fo`
    fall back to snacks' native `files`/`grep` (rg as a **subprocess** → non-blocking
    and complete).
  - `plugins/fff.lua` also has `enabled = not vim.g.is_rhel6`, because
    `lazy/fff/plugin/fff.lua` otherwise calls `ensure_initialized()` on `UIEnter` and
    would index the NFS tree on its own (`vim.g.fff.lazy_sync` is the plugin-level
    switch). Disabling the spec means no indexing, no autocmds, no `.so`.
  - Non-RHEL6 keeps fff (local disks → a single `content_search` call is ~ms), with
    `page_size = 200` and no `time_budget_ms` override. Do NOT reintroduce the
    `file_offset` paging/"hot"/chunking experiment that lived here for a while — it
    was reverted (see git history) as too complex for the win.
  - `Snacks.picker`'s own matcher is left alone; the fff grep source only adds
    `sort = false` (fff already ordered the hits) and disables the matcher *bonus*
    scorers. Never touch `fuzzy`/`regex`/`smartcase`: the matcher also does the
    regex/fuzzy filtering **and** supplies highlight positions, so a plain substring
    filter would drop every regex/fuzzy hit.
- **fff respects `.gitignore`** (like ripgrep's default): files under ignored dirs
  are invisible to fff grep (native rg behaves the same). Verify with
  `rg -n "pat" .` vs `rg -n --no-ignore "pat" .` and `git check-ignore -v <f>`; to
  search ignored files use a native picker with `ignored = true`
  (`Snacks.picker.smart`) or `vim.g.fff_mode = "off"`.
- **fff is glibc-sensitive — none of upstream's Linux prebuilts run on RHEL6:**
  - `x86_64-unknown-linux-gnu` → linked for glibc **2.31** (upstream CI: "Rust 1.91+
    requires glibc >= 2.31 … earlier targets (2.17) no longer link").
  - `x86_64-unknown-linux-musl` → **dynamic** musl (`DT_NEEDED libc.so`); dlopen
    into a glibc Neovim fails with `/usr/lib64/libc.so: invalid ELF header`.
  So we **cross-build our own** glibc-2.17 `.so` (rust 1.90 + cargo-zigbuild) with
  `scripts/build-fff-rhel6.sh`, which writes `scripts/prebuilt/fff/libfff_nvim.so`
  (**gitignored** — build it locally before packaging). The packager copies it to
  `data/lazy/fff/target/release/libfff_nvim.so`; fff's `binary_exists()`
  short-circuits so the plugin never auto-downloads the wrong build. Rebuild when
  the fff plugin commit changes — see "Rebuilding the fff RHEL6 binary".
- **Highlight gap-fills live in one table: `lua/box/hl.lua`** (applied from
  `box.setup()`, re-applied on every `ColorScheme`). It owns the groups the
  colorschemes don't define: `BlinkCmpKind{Variable,Folder,Reference,Color}` +
  `BlinkCmpLabel{Detail,Description}`, the six `GitSignsStaged*`,
    aerial's extra SymbolKind groups, and `DropBar{Kind,IconKind}Task{,NC}`. Reasons, all verified:
  - **A compiled colorscheme opens with `hi clear`, which drops EVERYTHING set
    outside it — including `default = true` groups.** So a one-shot
    `nvim_set_hl` in a plugin's `config()` (aerial's, gitsigns' staged links)
    is silently lost after `<leader>uC` switches themes. That is why the old
    per-plugin copies needed their own `ColorScheme` autocmd (dropbar's) — they
    are gone, `box_hl` does it for all of them.
  - **`link` combines with attributes**: `{ link = "DiagnosticError", bold = true }`
    takes `bold` from the table and falls back to the link for `fg`.
  - **`default = true` loses to a group the owning plugin already declared with
    `hi default`**.
  - blink's `highlights.lua` sets *every* group with `default = true`, so the
    `BlinkCmp*` entries win regardless of augroup order.
  Taste overrides that aren't gap-fills (`CursorLine`, `FloatTitle`,
  `@punctuation.bracket`) stay in the colorscheme's own `opts.highlights` in
  `plugins/ui.lua`. `box/picker_hl.lua` (called from `plugins/snacks.lua`) is
  the same idea for snacks' picker windows — that one works around snacks'
  winhl model, not a theme gap, so it is not a group table.
  - It patches `Snacks.picker.highlight.winhl` so each picker window also remaps
    `Normal`, and strips the bg off `LineNr`/`NonText` so everything linking
    them falls back to the float bg. The winhl wrapper compares the current
    function against its own closure: wrapping twice (a `:Lazy reload
    snacks.nvim` re-runs `config()`) would append `,Normal:..` per reload, and
    an identity check re-wraps correctly when snacks comes back as a fresh
    module. Do NOT stash the marker on the function itself — indexing a function
    value is a hard Lua error, not nil.
  - It keeps its own `box_picker_hl` ColorScheme autocmd because no replay
    covers what it does: it strips the bg off existing theme groups
    (`LineNr`/`NonText`) and its `SnacksTitle`/`SnacksFooter` go through
    `set_hl{managed=false}`, which opts out of snacks' `snacks_util_hl` replay.
    The callback is `vim.schedule`d, so the fix lands a tick after the theme
    switch — harmless, nothing can be mid-picker while switching.
- **`blade2049` is a catppuccin flavour, not a standalone colorscheme**
  (`lua/box/colors/blade2049.lua` + `plugins/ui.lua`'s catppuccin spec +
  `lua/catppuccin/palettes/blade2049.lua` + `colors/catppuccin-blade2049.lua`).
  Full rationale, the measured numbers and the exit criterion are in
  `docs/adr/0002-catppuccin-flavour-for-blade2049.md`. What is load-bearing
  here, all verified:
  - **The design is MUTED BASE + NEON ACCENTS**, which is the film's own logic:
    Los Angeles is rendered as cold, low-saturation blue-grey, and everything
    that *is* a light source — the spinner, K's eyes, the sodium lamps, every
    in-world display — burns at full chroma on top of it. Greying the accents
    too is the mistake to avoid, not the mistake to avoid making; a "faithful"
    all-grey version loses the only thing the film is about.
  - **The palette is split LOUD vs QUIET, and the split is driven by how often a
    token appears, not by how important it is.** LOUD (high chroma, *mid*
    brightness) = the six things you scan for: `mauve` keyword/control flow,
    `yellow` function, `blue` type/module/directory, `pink` preproc/special,
    `teal` string, `peach`+`green` number/Ok, plus `red` for errors only.
    QUIET (desaturated) = plain structure: `flamingo` bone identifier, `maroon`
    tan parameter, `overlay2` comment/delimiter/bracket.
  - **Loudness is NOT brightness, and this is the load-bearing idea.** Body text
    is 12.0:1 on base; the loudest accent (keyword purple) is 6.55:1 — a neon
    that dims *toward* the background. At equal luminance a screen of
    `if / for / return / else / while` becomes a solid purple wall, because
    keywords are the highest-frequency token in code.
  - **That is also why parameters are tan and not pale orange.** Measured: a
    light orange parameter came out at 9.74:1 × 100% sat and *beat* keyword
    purple (6.55:1 × 100% sat) as the loudest thing on screen — and parameters
    are as frequent as keywords. Quiet them or the hierarchy inverts.
  - **The palette alone carries most of the design**, because catppuccin's
    slot→role map already lands it (`mauve` drives Keyword/Conditional/Repeat/
    Statement/Exception/Include, so all six become purple for free). The
    18-entry `overrides()` only moves roles that would mean something else —
    `Function` (default `blue`), `Type` (default `yellow`, which would make a
    type read as a call), `String` (default `green`), `@type.builtin` (must not
    be `mauve`, that is keywords), `@variable.builtin` (default `red`; `self`
    appears in nearly every method and red stays scarce), and `Todo` /
    `@comment.todo` (default `flamingo`, which is bone now — a bone highlight
    bar is off-palette).
  - **All 26 slots must be filled, and they must be plausible**, not just the
    ones we use: catppuccin's own `groups/` reference them (`@variable.builtin`
    = red, `@module` = yellow, `@type.builtin` = mauve, …).
  - **Register the flavour inside the spec's `opts` FUNCTION, and the placement
    is load-bearing.** `catppuccin/init.lua` validates `flavour` against a
    hardcoded `M.flavours = {latte, frappe, macchiato, mocha}`, and `setup()`
    only recompiles what it finds there. The one point that is guaranteed to
    have catppuccin on the rtp *and* to run before `setup()` is the `opts`
    function itself — lazy evaluates it as an argument of
    `require(main).setup(opts)` (`lazy/core/loader.lua`, `M.config`), after
    `packadd`. Both alternatives are broken here:
    - module scope — `require("catppuccin")` fails (plugin not on the rtp yet)
      and the whole spec file fails to import;
    - the `init` hook — *measured*: a cold-cache `setup()` recompiled the four
      official flavours, skipped blade2049, and `M.compile()` wrote `cached`
      anyway, so stale colours survived every later start **with no error
      anywhere**. A miss is invisible by construction: `compiler.lua:74-92`
      prints a dump and `return`s if the generated source will not `loadstring`,
      and `setup()` does not check that every flavour got written.
    Verify a palette edit actually landed:
    `strings ~/.cache/nvim/catppuccin/blade2049 | grep -c <new hex>`.
  - **`color_overrides` cannot stand in for the palette file.**
    `palettes/init.lua:5` is `local _, palette = pcall(require, ...)`, so a
    missing module hands pcall's error *message* (a string) to the
    `tbl_deep_extend` on the next line and it rejects it. Hence the one-line
    `lua/catppuccin/palettes/blade2049.lua` adapter rather than config only.
  - **`highlight_overrides` must be a plain table, not a function.**
    `lib/hashing.lua:17` hashes a function as `fn(get_palette())`, and at
    `setup()` time `get_palette()` returns **mocha's** palette — so editing one
    of our hexes would leave the compiled cache valid and the theme would
    silently keep the old colours. `plugins/ui.lua` builds the table eagerly
    with `overrides(palette)`. (`lib/mapper.lua:64` also replaces a function
    entry with its result, mutating the options table.)
  - **`:CatppuccinCompile` ends on mocha** — it finishes with
    `colorscheme catppuccin-nvim` and `options.flavour` is already consumed.
    Re-apply `:colorscheme catppuccin-blade2049` after compiling.
  - **Palette slots encode RELATIVE contrast, so changing the hexes changes
    them.** This ramp is tighter than mocha's, so three inherited values landed
    too dark: `LineNr` 1.20:1 (mocha 1.80), `TabLine` 1.94:1 (mocha 3.84),
    `CursorLine` 1.05:1. All three are re-picked in `overrides()` with the
    measured ratios in the comment — re-measure them if the neutrals move.
  - **`IncSearch` is load-bearing for aerial**: `hl.lua` links `AerialLine` to
    it, and catppuccin's `IncSearch` is `fg=mantle` on a near-base bg (an
    outline symbol you cannot see). The override fixes the search highlight and
    the aerial symbol in one line.
  - Measured contrast on `base`: body text 12.0:1; the loudest accent
    (keyword) 6.55:1; the lowest *text* role (`Comment`) 4.67:1 clears WCAG AA;
    `overlay0`/`overlay1` are below on purpose — line numbers, `Conceal` and
    `Dimmed` are not text. The notifier's three levels come out as
    info = blue, warn = orange, error = red.
  - **To retune, pull a SLOT, not an override.** The six LOUD hexes are marked
    in the palette table. If the screen turns to confetti, pull `mauve`
    (keyword) down first — it is both the loudest and the most frequent.
- **Noice suppresses `recording @a`** (`msg_showmode` is `skip`-routed). lualine
  shows a `REC @<reg>` indicator instead, refreshed on `RecordingEnter`/`Leave`
  (`plugins/ui.lua`).
- **The RHEL6 wakatime 104 is permanent noise, and noice routes it out.** The
  plugin reports every failed heartbeat with `vim.notify` (`lua/wakatime/init.lua`),
  and on the air-gapped box the failure *cannot* be fixed: `api_url` is the
  `127.0.0.1:1` placeholder, so wakatime-cli can never validate the api key and
  exits 104 — once per `heartbeat_rate_limit_seconds` window, forever. Loopback
  means **zero egress** (do NOT "fix" it by pointing `api_url` at the real wakapi
  — that is what would generate outbound DNS/TCP). `plugins/ui.lua` drops it via
  noice's documented `routes` + `opts.skip` (`filter = { event = "notify", find =
  "%[WakaTime%]" }`), gated on `is_rhel6` so a networked box still sees genuine
  notifications. Wrapping `vim.notify` instead would fight whoever owns the
  notify handler. Caveat: noice is `VeryLazy`, so the message echoes once before.
- **bufferline duplicate prefixes on Windows** (`plugins/ui.lua`, the bufferline
  `config`): nvim *always* normalises buffer names to `/` (even when opened with
  `\`), but bufferline derives `utils.path_sep` from `has("win32")` = `\` and
  splits on it -> the split yields a single component, duplicate detection bails
  at depth 1, and `Component:__ancestor` returns a bare `\` (its `dir == ""` guard
  can't fire because the separator is already appended) -> two buffers named
  `view.lua` both render as `\view.lua`. Fix: after `require("bufferline").setup`
  set `require("bufferline.utils").path_sep = "/"` (no-op on Linux; `path_sep` is
  display-only — used in `models.lua` + `duplicates.lua`).
- **`glibc234` tools** (node/pandoc/clangd/lua-language-server) on RHEL6 are
  patchelf'd to a glibc-2.34 loader and wrapped to `unset LD_LIBRARY_PATH`
  (see `scripts/install-offline.sh`). Never export `LD_LIBRARY_PATH`.
- **Bulk file rename from the picker** (`<a-n>` → action `rename_replace`,
  `plugins/snacks.lua`): renames the **basenames** of the selected (or cursor)
  picker items with a **Lua-pattern** search/replace pair (`%1` captures, not
  `\1`). Reuses `Snacks.rename.rename_file`, which degrades to a plain
  `vim.fn.rename` when no LSP client supports `workspace/willRenameFiles` (it just
  skips clients) — so it works on the offline box where LSP may be absent.
  Targets that already exist are skipped, never overwritten. Deliberately
  basename-only with a confirm list (no in-picker preview) to stay small.
  NB: a *named* action is resolved via `Snacks.picker.config.action(picker, name)`
  from `picker.opts.actions` — **not** `Snacks.picker.actions[name]` — so headless
  probes must invoke it via
  `require("snacks.picker.core.actions").resolve(name, picker, name).action(picker)`.
- **Notifier enter/exit animation** (`box/anim/`, configured in
  `box/notifier_anim.lua`, hooked from `plugins/snacks.lua` via
  `styles.notification.on_win` = `notifier_animate_in`): two INDEPENDENT effects,
  each optional via `enable` (or the whole table set to `false`):
  `slide` unfolds the width from 2 cells to full with a fixed right edge (nvim
  clamps floats on-screen, so an off-screen slide is impossible); the exit shrinks
  to 2 then really closes (an instance-level `close` override animates before the
  close lands). `fade` dissolves the highlight groups toward the editor
  background. Both run as their own `Snacks.animate` pass at 120fps with a
  closed-form critically-damped spring (`box/anim/spring.lua`) as the easing, so
  the fade is no longer quantized by the integer width.
- **`box/anim` is a generic window-animation framework, not notifier code.**
  `box/anim/core.lua` owns the mechanics and knows nothing about notifications
  or snacks Win objects — but it is NOT independent of snacks: `Snacks.animate`
  still schedules the frames and `Snacks.util.blend` still mixes colours. The
  decoupling is from the snacks *window model*, not from the engine. Effects, the
  enter/exit direction, landing the first frame immediately, and cleanup live
  here. Two entry points:
  - `require("box.anim").attach(opts)` -> a snacks `on_win` hook. The snacks
    adapter (`box/anim/init.lua`) is the only place that touches a snacks Win
    object: it reads the target geometry from `win:win_opts()` (the *intended*
    layout, which survives a re-layout better than the live config), installs the
    `close`/`update` overrides, re-asserts the winhl once visible (see the ns
    quirk below), and gates on `Snacks.animate.enabled`.
  - `require("box.anim").new(opts)` -> a runner usable on ANY window:
    `runner:enter(winid)`, `runner:exit(winid, finally)`,
    `runner:stop(winid)`, `runner:resume(winid)`. Use it for a picker/dashboard
    float you open yourself with `nvim_open_win`.
  State is keyed by **winid** (a fresh snacks Win object is created per
  notification, and raw floats have no object at all), and a `WinClosed`
  autocmd releases the session so a window destroyed underneath the animation
  cannot leak a namespace slot or leave `wrap` set.
  Adding a new target is config + (for extmark-drawn content) a `fade.groups`
  list -- the core and effects need no changes. `slide` only needs a float's
  col/width; a leaf/split would need a different (resize) effect.
- **The fade discovers its groups, so a target usually needs no config.** It
  collects: every `from:to` in the window's own `winhighlight` (redefined in the
  ns with `to`'s resolved colours); `Normal`/`NormalNC`/`NormalFloat` and the
  `FloatBorder`/`FloatTitle`/`FloatFooter` ring (skipped when the winhl already
  maps them); the extmark groups actually used in the VISIBLE range (the
  notifier's separator/title/icons, picker items); the float title/footer chunk
  groups (`get_config().title`/`footer`); `%#Group#` names in the window's
  winbar/statuscolumn (Snacks.input's icon); and anything the config passes as
  `fade.groups` (list or `fun(aw, winhl): string[]`). A window with an empty
  winhl and no discovered groups is not faded (the effect reports "skip").
  Syntax/treesitter highlights are not extmarks, so a window styled only by
  syntax (e.g. the picker preview) cannot fade from here.
- **`nvim_buf_get_extmarks(buf, ns, start, end, opts)` takes `(row, col)`
  TUPLES for start/end** — a bare integer is read as an extmark id, and gets
  "Invalid mark id (not found)" instead of failing loudly. The fade's discovery
  silently found nothing until this was fixed, which is why the earlier
  hand-written `fade.groups` for the notifier looked necessary.
- **The fade fades the WHOLE window through ONE mechanism: a window-local
  highlight namespace** (`box/anim/fade.lua`) that redefines every group the
  notification uses — the window groups (`Normal`/`NormalNC` for the text,
  `NormalFloat` for the float background, `FloatBorder`/`FloatTitle`/
  `FloatFooter` for the border ring) and the style's extmark groups (the fancy
  style draws icon/title/separator with extmarks). **Do not "simplify" this back
  to winhl remaps** — an earlier version did that and it silently faded only the
  extmark groups, because of the ns quirk in the next bullet.
- **Never read theme colours with `Snacks.util.color` inside the animation.**
  It calls `nvim_get_hl(..., link = false)`, and that variant starts reflecting
  the **current window's winhighlight** once nvim has applied it (measured:
  identical to the plain read while synchronous, `nil` on the next tick). The
  animation always runs after ticks, so with a window mapping `Normal` (every
  animated picker/input) the editor background came back as the card colour (the
  fade silently became a no-op) and `Normal`'s fg as nil (the body would not
  fade). The notifier happened to dodge it — its windows are opened with
  `enter = false`, so the editor stays current — but a focused float hits it
  immediately. Use the plain `nvim_get_hl` (via `fade_base`, which also follows
  links itself).
- **nvim winhl/ns quirks (verified with screen-attr probes — do not "simplify")**:
  (a) a winhl applied while the window is still hidden is never picked up —
  `on_win` re-asserts it once visible; (b) **`nvim_win_set_hl_ns` makes nvim ignore
  the window's winhl PERMANENTLY** — re-setting the winhl afterwards (via `vim.wo`
  or `setwinvar`, in either order) does NOT revive it, which is what broke the old
  winhl-based fade; the namespace alone reaches every group the window uses
  (verified: defining `Normal` recolours the text, `NormalFloat` the fill,
  `FloatBorder` the ring); (c) `nvim_win_set_config` does not reset the ns, and
  detaching it (`ns = 0`) leaves the winhl inert again, hence the detach-then-
  re-assert ordering in the fade's clear.
- **Namespaces can't be deleted, so the fade's ns instances live in a 64-slot
  pool** and the names are `box_anim_fade_*` — never reuse a namespace name
  that ever held different group definitions (stale definitions take precedence
  and silently break colors; the pool exists so a fresh name is never needed
  for a window that reuses a slot).
- **A dark accent cannot be faded into lockstep with light text.** The fade gives
  every group the same alpha (`fade.contrast = 0`), which keeps each group's
  brightness-above-the-background ratio constant — genuinely in sync. The
  optional `contrast` knob instead bisects each accent toward the body's
  luminance, but a group can never end up brighter than its own full colour, so an
  accent darker than the text saturates early and then freezes (measured: error's
  `#e06c75`, WCAG contrast 4.38 vs the body's `#abb2bf` 6.57, hit full colour at
  ~60% of the animation). The `contrast` target is clamped to what the group can
  reach so it saturates on purpose. Fixing the remaining lag needs a brighter
  error accent, not animation tuning.
- **Both effects must flush their own frames** (`nvim__redraw{win, flush=true}`
  per frame): highlight updates otherwise sit in nvim's cache until some unrelated
  redraw, so the fade renders freeze-then-jump — and with `slide` disabled there
  is no other flusher at all.
- **Windows timer resolution caps the animation** (`box/anim/core.lua`): the
  default ~15.6ms quantizes uv timers (an 8ms interval fires at ~15.6ms; 16ms rounds
  up to 31ms) → ~64fps. `timeBeginPeriod(1)` (winmm via LuaJIT ffi, Windows-gated,
  auto-released on exit) unlocks ~8.5ms ticks so the animation can run at 120fps.
  `fps` plus the per-effect `frequency`/`damping`/`settle` springs live in
  `box/notifier_anim.lua`.
- **Sessions are `mini.sessions`** (`plugins/editing.lua`; persistence.nvim was
  removed and its old per-cwd session files deleted): named global sessions under
  `stdpath("data")/session/`, `<leader>ps` smart-saves (prompts for a name only when
  no session is active — `v:this_session` is set by BOTH read and write, so the
  first save activates autowrite), `<leader>pl` writes the project-local
  `Session.vim`, `<leader>pr` restores the latest, `<leader>pc` selects, `<leader>pd`
  deletes. `autowrite = true` writes back only the current
  session on exit — it never creates sessions for other directories.
- **mini.animate** (`plugins/editing.lua`): split-resize only, 150ms cubic. `cursor`
  off — it draws a **buffer-wide extmark**, so with the same buffer in two windows
  the flying mark shows in both ("two cursors"; mini's own guard only compares the
  buffer id, missing same-buffer window switches). `scroll` off (snacks.scroll
  already animates scrolling), `open`/`close` off (their default predicate matches
  ALL windows incl. floats, which would fight the picker/notifier animations).
  Gated off on `vim.g.is_rhel6`.
- **hardtime breaks any wrapped key whose `lhs` nvim normalizes — measured on
  `<`.** `enable()` wraps every key of `resetting_keys` + `restricted_keys` +
  `disabled_keys` (ALL THREE groups, `init.lua:189-193`) in an expr mapping that
  resolves the original through `get_return_key`, matching `lhs` against its
  `nvim_get_keymap("n")` snapshot. That snapshot spells a `<` mapping as **`<lt>`**,
  so the lookup for `"<"` misses, the wrapper returns the bare key, and normal
  `<` (Indent left, `core/keymaps.lua`) silently does nothing — while `>` kept
  working only because `>>` is a builtin. `<`/`>` are in the default
  `resetting_keys` (`config.lua:36-37`), so exempting them under
  `restricted_keys` changes **nothing** (measured). Both are exempted in
  `plugins/hardtime.lua` under `resetting_keys`; `false` means "remove" because
  of the `tbl_deep_extend("force", ...)` merge (`init.lua:243`) plus `if mode then`
  (`init.lua:197`). hardtime's `setup()` merges user opts in a **500 ms timer**,
  so a probe that calls `enable()` by hand wraps the keys with the DEFAULTS and
  the exemption appears to do nothing — wait for `is_plugin_enabled` instead.
- **Colemak-DH** (`box/colemak.lua`, `<leader>uk`, **off by default** = qwerty).
  The layout is installed system-wide, not from this config, so the toggle is the
  only coupling. Derived from the official `colemak_dh_ansi_us.klc`, read off its SC column against
  the standard PC/AT set-1 scan codes (0x1e-0x27 is the home row, 0x28 is the
  apostrophe, 0x2b is the backslash, 0x39 is space). Its VK_ column is **not** a
  position oracle -- it has been rewritten to the produced character, so reading
  it shifts the whole bottom row one key. That puts **`m`@H `n`@J `e`@K `i`@L** and **`h`@M `j`@Y `k`@N `l`@U `u`@I** —
  so vim's `h` ends up on the M key, and hjkl is the one thing worth fixing. The
  module translates each produced letter back to the command its QWERTY key ran,
  in normal mode only: **`i`/`a` are prefixes for text objects in visual and
  operator-pending mode**, so remapping `i` there would break every `viw`/`di(`.
  `u`/`i` are a 3-cycle (`i`@L, `l`@U, `u`@I) and all three are mapped, or insert
  mode becomes unreachable. Deliberately NOT remapped: `y`, whose slot moves too
  (Colemak-DH puts it on the O key), so physical O stays a yank key.
  - **Overlapping mappings are snapshotted and restored, not re-declared.**
    `h`/`j`/`k`/`l` are not ours: `hardtime` rate-limits them with an expr
    mapping wrapping a Lua callback (`restricted_keys` covers `"n"` **and**
    `"x"`), and hardtime is `lazy = false`, so it installs them *after*
    `box.setup()`. Re-declaring `j` would kill hardtime's mapping for good, and a
    re-declared     mapping cannot be un-done. So `enable()` does
    `maparg(lhs, "n", false, true)` first and `disable()` rebuilds it — that dict
    *does* hand back `callback`/`expr`/`noremap`/`silent`/`desc`. Verified by
    round-tripping a synthetic expr mapping. `plugins/hardtime.lua` is therefore
    left alone, and an install that never presses the toggle sees nothing at all
    (`M.setup()` only registers the key).
  - Caveat: `<leader>um` (hardtime disable/enable) re-runs hardtime's own
    `enable()`, which re-declares `h`/`j`/`k`/`l` and so overwrites 4 of the 9
    swap entries. Toggle off and on again after touching it.
  - In the **ON** state hardtime's `hints` also go silent by construction: they
    are matched by `vim.on_key()` (`hardtime/init.lua:251`), a raw key hook that
    runs *before* mapping resolution, against `config.hints` -- a table entirely
    separate from `restricted_keys`. Pressing physical H/J/K/L emits `m/n/e/i`,
    so patterns like `%D1[hjkl]` and `[^fFtT]li` ("Use a instead of li") can no
    longer match. Nothing to fix, but do not be surprised by it.
  - **There is deliberately no "start enabled" path.** hardtime's own `M.setup()`
    defers 500 ms (`hardtime/init.lua:313`) and it is `lazy = false`, so its
    mappings land ~1.1 s past `VimEnter` — measured, and also after `LazyDone`
    (162 ms), the first `BufEnter` (275 ms) and `User VeryLazy` (which does not
    fire headless at all). No startup event is reliably after it, so enabling
    from a hook would snapshot the wrong mappings and hardtime would then
    overwrite 4 of the 9. The `<leader>uk` press is the only entry point;
    `vim.g.colemak_keymaps` is session state only, never read at startup.
  - **`<leader>uk` is a `Snacks.toggle`** (`id = "colemak_keymaps"`), built lazily
    on first press exactly like `box/project.lua`'s auto_cwd: `box.setup()` runs
    before `lazy.setup()`, so `Snacks` does not exist yet, and the toggle's
    `:map` then overwrites the plain keymap `M.setup()` registered. It buys the
    on/off icon + colour in which-key's `<leader>u` group and snacks' own
    "Enabled/Disabled Colemak-DH" notification, so the hand-rolled
    `vim.notify` in `flip()` is gone. `Toggle:toggle()` passes the *target*
    state to `set`, which is why `flip()` no longer reads the flag itself.

## Treesitter parsers & the systemverilog fork

- Parser list: `lua/box/parsers.lua` (27 langs).
- `systemverilog` is overridden to the personal fork
  `https://github.com/lwflwf1/tree-sitter-systemverilog` (dynamic `master` tracking)
  in `plugins/treesitter.lua`.
- **SV queries are split between the fork and this config.** The fork's
  `install_info.queries = "queries"` makes nvim-treesitter **copy** that dir into
  `site/queries/systemverilog` on every install (`install.lua:441-443` →
  `do_copy_queries`), so `folds/highlights/indents/injections/textobjects` ship with
  the parser — do NOT keep config copies of those: `queries/` sits earlier on rtp
  than `site/`, so a stale local copy silently shadows the fork's version.
- What must stay in `queries/systemverilog/` + `after/queries/systemverilog/`,
  because the fork does not ship it: `aerial.scm` (aerial's backend),
  `function_arguments.scm`, `function_body.scm`, `function_definition.scm` and
  `variables.scm` (hlargs.nvim loads those four names in `lua/hlargs/parse.lua`), and
  `after/queries/systemverilog/context.scm` (treesitter-context loads the `context`
  query). When moving a query into the fork, delete the config copy in the same
  commit and check `git hash-object` against the fork's blob sha.
- `:ToolInstall` installs missing mason tools from `box.lsp` + `plugins/formatter`
  and missing parsers; `:ToolUpdate` refreshes mason registry + parsers.
- **Never hand-copy `lazy/nvim-treesitter/runtime/queries/<lang>` into
  `data/site/queries/<lang>`** (this config used to do exactly that, and the
  advice used to live here). `install()` decides a language is out of date with
  `fs_realpath(site/queries/<lang>) ~= fs_realpath(runtime/queries/<lang>)`
  (`install.lua:178-183`), so a real directory is *always* "different" → install
  tries to `fs_symlink` over it → `[nvim-treesitter/install/<lang>] error: EEXIST:
  file already exists`. `do_link_queries` can only `uv_unlink`, which fails on a
  non-empty directory, so the error cannot be retried away. Fix: delete the
  directory and let nvim-treesitter link it — `site/queries/<lang>` should be a
  junction/symlink into `runtime/queries/<lang>` (all 20 of ours are), never a
  directory. Re-check after a plugin update with the audit below.
- **Queries must live under an rtp `queries/<lang>/` dir.** `nvim-treesitter` (main
  branch) keeps its queries in `<plugin>/runtime/queries`, which is **not** on rtp;
  `install()`/`:TSUpdate` links them into `site/queries/<lang>`. Because
  `install()` skips already-installed parsers, a parser can exist with **no base
  query** → treesitter starts, captures nothing, and the regex syntax is off →
  **no highlighting** (keywords like python `def`, go `func`, rust `fn`). A theme/plugin
  `after/queries/<lang>/highlights.scm` (`; extends`) does **not** count as a base
  and can mask the problem: `vim.treesitter.query.get()` returns non-nil while
  only theme captures exist. Check the *sources*, not just non-nil — audit all
  parsers after an update:

```lua
  -- headless probe: prints nothing when every parser has a base highlights query
  for _, lang in ipairs(require("box.parsers")) do
    local base = vim.tbl_filter(function(f)
      return not f:match("after[\\/]queries")
    end, vim.treesitter.query.get_files(lang, "highlights"))
    if #base == 0 then print("no base highlights: " .. lang) end
    if not vim.uv.fs_stat(vim.fs.joinpath(vim.fn.stdpath("data"), "site", "parser", lang .. ".so")) then
      print("missing parser: " .. lang)
    end
  end
  ```

  A lang that fails the first check needs
  `require("nvim-treesitter").install(require("box.parsers"), { force = true })`
  (or deleting the stale `site/queries/<lang>` directory first).

## Local AI model (cursortab's backend)

`plugins/cursortab.lua` points at a **local llama.cpp server on
`http://localhost:8000`**. Nothing in this config starts, downloads or supervises
it — by design: the editor must not own the process, and a first-request cold
start would otherwise land inside the typing pause.

The model is Zed's **zeta-2.1** (SeedCoder-8B) as GGUF. Sizes on HF
(`mradermacher/zeta-2.1-GGUF`, 8.25B params, ctx 32768, Apache-2.0):
Q4_K_M 5.07 GB, Q5_K_M 5.90 GB, Q8_0 8.77 GB. This box is 16 GB, so Q4_K_M is the
default; Q8_0 leaves too little headroom and a NES payload is only tens of tokens.

```
llama-server \
  -hf mradermacher/zeta-2.1-GGUF:Q4_K_M \
  -a zeta-2.1 --port 8000 -ngl 99 -fa -c 16384 --no-webui
```

- **`-a/--alias`, NOT `--served-model-name`.** Verified against the installed
  `llama-server 0.6.0` (`--help`): only `-a` remains. blink-edit's README still
  prints the old spelling, which errors out. Nothing has to match the alias —
  `provider.model` is deliberately left unset so cursortab reads it off
  `/v1/models`, which is one less thing to keep in sync.
- **`-c 16384`, not the model's 32768**: halves the KV cache, which is most of
  the p50 on a bandwidth-bound M4.
- Start it from **launchd** (KeepAlive), not from `init.lua` and not from the
  cursortab daemon. The daemon outlives nvim and reads its env only at start
  (`:CursortabRestart` after changing anything), so co-owning the model would
  put two long-lived processes behind one toggle.

**Measured throughput on this M4 — and what it does NOT mean.** Every figure
below is measured, and the sanity check that settles "is something broken?" is
`llama-bench -m <gguf> -p 512 -n 64`, which on this box reports
`pp512 = 202 t/s` and `tg64 = 20.8 t/s` for the same 4.72 GiB Q4_K_M:

| | measured | vs. `llama-bench` |
|---|---|---|
| decode | 14.7–20.0 t/s | 71–96% (the rest is server overhead: KV writes, slot scheduling, `--cache-reuse`) |
| prefill, 1500–5200 token prompts | 107–174 t/s | not comparable — `pp512` measures *512*-token prompts, and attention is quadratic |

**This is normal for an M4, not a misconfiguration.** Decode is weight-read
bound: 4.72 GiB / the M4's 120 GB/s = 23.7 t/s theoretical, so 14.7–20 t/s is
62–85% effective bandwidth — squarely in the band llama.cpp gets on Apple
Silicon. Prefill is compute bound at ~2.9 TFLOPS effective against an ~8–9
TFLOPS FP32 peak, i.e. ~33%: normal for Q4_K_M, whose matmul dequantizes to
FP32 and never touches tensor cores (`has tensor = false` on Apple9).

Three dead ends worth not re-walking:

1. **"The Metal backend is missing."** It is not — `libggml-metal.so` is a
   runtime-dlopen'd backend and `:MTL0` never appears at `-lv 3`. `-lv 5` prints
   `MTL0 : Apple M4`, `load_tensors: layer N assigned to device MTL0` for all
   layers, and `n_threads = 10`. Reading a missing log line as a missing feature
   is the whole error.
2. **"EOS is broken, zeta-2.1 will never stop."** The GGUF metadata is fine
   (`eos_token_id = 2`, `token_type = 3` CONTROL, 128 EOG tokens; verified by
   range-fetching the file header and parsing the KV). The probe that "proved"
   it wrong sent a BARE prompt, so the model had no turn boundary to stop at
   and correctly kept writing code forever. cursortab sends the V0318 prompt, and
   it converges: with `n_predict = 512` the observed `n_gen` tops out near 119.
3. **"Prefill is an order of magnitude too slow."** That compared a *guessed*
   GPU peak against an effective throughput. Judge decode against bandwidth
   and prefill against `llama-bench`, not against a remembered TFLOPS figure.

**Where the latency actually goes, and the one lever that matters.** p50 is 79
generated tokens × 50 ms/token. Prefill is nearly free because
`--cache-reuse 256` reuses the whole prompt prefix (identical `n_past` before
and after reuse). So no request-side tuning moves latency — the model's tok/s is
the only lever, which means the hardware, or a smaller model.

**Why zeta-2.1 and not zeta-2**, given zeta-2 actually scores higher
(0.61 vs 0.57, deltaChrF 65.4 vs 60.6) in cursortab's own 50-scenario eval:
zeta-2.1 was picked anyway. Both have a 100%/96% quiet rate; the difference is
that **zeta-2.1 is main-only** (see the `version = false` bullet), so choosing it
is the same choice as tracking main. zeta-2's win is real but small, and its
lower latency is the least important axis here — a NES prediction that lands at
800ms and one at 550ms feel the same when you are still typing the line that
provokes it. Revisit if `sweep`/small-FIM options ever get benchmarked here.

**Three targets now.** `enabled = not vim.g.is_rhel6` means this loads on macOS
*and* Windows, not just the offline box: both need Go 1.25+ for
`cd server && go build` plus a running model server, and neither gets one from
this repo. macOS was already a real target in `init.lua`
(`vim.g.os == "macos"`) but is not described in "What this is" above — fix that
doc if the two-target framing is meant to stay accurate.


## wakatime / wakapi (coding-time tracking)

`lua/plugins/wakatime.lua` (+ `lua/box/wakatime.lua` for the `:WakaExport` /
`:WakaSync` commands) and the official
`wakatime/vim-wakatime` plugin, server = self-hosted **wakapi** (Go, static binary)
on the fnOS box. Data model: the CLI POSTs *heartbeats*; wakapi derives durations
from the **gaps between consecutive heartbeats** (`services/duration.go`: per-user
`timeout` (default 10 min) caps each gap, `heartbeatPadding = 0`, cross-day gaps are
dropped, a range holding a single heartbeat counts 0). So idle time is never
counted, and "touching nothing" records nothing — the plugin only emits on
CursorHold with activity in the last 120s, on every BufWritePost and on BufEnter.

- **Nothing about wakatime is set up from Lua; the installers own it.** Two things
  must exist before nvim starts, and both are written by `install-offline.sh`
  (RHEL6) / `install.ps1` (Windows, online):
  `~/.wakatime/wakatime-cli` (symlink to `~/.local/bin/wakatime-cli-linux-amd64`,
  copy fallback) and `~/.wakatime.cfg`.
  Do **not** move either back into `lua/box/`: a config file should not mutate the
  filesystem on every startup, and — critically — `opts` merges **after**
  `plugin/wakatime.vim` has already called `require('wakatime').setup()`, whose
  `setup_cli()` latches the first CLI path it finds (`state.cli_already_setup`). A
  later `opts.cli_path` updates `state.config` but leaves `state.wakatime_cli`
  pointing at the (non-existent) managed path, and `send_heartbeats()` then
  **silently drops the buffer on every event**. Only `status_bar_enabled` survives
  that late merge (it is re-read on every `statusline()` call).
- **`~/.wakatime.cfg` is only written when absent, never edited** — it holds the api
  key set via `:WakaTimeApiKey` (or `$WAKATIME_API_KEY`, the one setting the CLI
  does read from the environment). `sync_ai_disabled` is set on RHEL6 only.
- **`hide_project_folder` is OFF, deliberately.** It is the wrong default here:
  it computes the relative path against `project_folder`, and only a detector
  that found a real project root sets that correctly. RHEL6's projects are not
  git repos, so they use `[projectmap]`, and the Map detector returns
  `filepath.Dir(entity)` (`pkg/project/map.go` — the whole `Result` literal) —
  the directory the file itself is in. With the setting on, every file would be
  sent as a bare basename and the directory structure lost. Off means the full
  path travels, which also puts `/proj/crane/wa/yingfangong/` (i.e. the username)
  in the data — fine for a self-hosted wakapi, worth remembering when sharing
  exports or screenshots.
- **RHEL6 `api_url` is `http://127.0.0.1:1/api`**: a routable-but-unreachable URL
  would block every heartbeat for the full `timeout` (default 120s) on a dead route
  or on a DNS query the intranet resolver never answers. Loopback port 1 is refused
  instantly and the heartbeat is queued either way. Online machines take theirs from
  `$WAKATIME_API_URL` at install time.
- **`status_bar_enabled` is false on RHEL6.** The plugin injects a lualine component
  that refreshes `wakatime-cli --today` every 60s, and `--today` is network-only
  (`cmd/today/today.go` has no offline branch and never reads the queue) — that is
  ~1440 doomed processes a day for an empty status line.
- **Manual replay flow (air-gapped RHEL6).** Heartbeats pile up in
  `~/.wakatime/offline_heartbeats.bdb` (bbolt, values are JSON). The bridge is
  **mail**: RHEL6 can reach only the corporate Exchange box, so the export is
  mailed to `<user>@asrmicro.com`, an Outlook rule moves it to `INBOX/wakatime`,
  and a networked machine pulls it back over IMAP. Two commands:
  - RHEL6: `:WakaExport` (`scripts/wakatime-export.sh`) — `--offline-count` →
    `--print-offline-heartbeats N` → `ferry pack -f zip` → `ferry email`, which
    splits at ferry's `SPLIT_SIZE` (exactly 1 MiB) and mails one message per
    part. Then it deletes the local .json/.zip **and the queue**.
  - Networked box: `:WakaSync` (`lua/box/wakatime.lua`, `ssh` not needed) —
    `ferry recv` pulls the parts out of the mailbox, then `ferry merge` →
    `ferry unpack` → POST to `<api_url>/users/current/heartbeats.bulk`.
- **The export half is deliberately NOT in Lua, even though it could be.** Two
  files implement this flow and the split is load-bearing: `wakatime-export.sh`
  owns everything that runs on RHEL6, `box/wakatime.lua` owns everything that runs
  on the networked box. The reason is the air gap: the export is a *data rescue*
  operation on a machine whose only editor is the nvim whose config might be what
  is broken, so it must keep working with nvim entirely out of the picture —
  `bash scripts/wakatime-export.sh` is the manual fallback, and `:WakaExport`
  only wraps it (locate, check bash, pass argv through, show output). Do not
  "unify" the two halves; if you find yourself reimplementing a queue count or a
  size check in Lua, it belongs in the script.
- **`vim.fn.glob` honours `'wildignore'`, and this config wildignores `*.zip`** —
  so every file lookup in `:WakaSync` must go through `readdir`
  (`list_files`/`find_files` in `box/wakatime.lua`), not `glob()`. The archives
  this feature looks for are `.zip`, exactly what `core/options.lua` appends to
  `wildignore`, and the failure is silent and misleading: `group_archives`
  returned empty and the sync reported `no archives in the staging dir` *while
  the downloaded archive was sitting in that directory*, with `ferry recv`
  having just logged `1 newly written`. Two wrong guesses cost a cycle — first
  blaming a filesystem race (it reproduced with the file already present), then
  blaming a broken download. Reproduce by running `:WakaSync` with a `.zip` in
  `~/wakatime-ferry/incoming`. Do NOT "fix" it by dropping `*.zip` from
  `wildignore` — ignoring archives in the editor's own completion/quickfix is
  correct; the lookup was wrong.
- **The mailbox half lives in ferry, not here.** `ferry recv` (`G:\ai\scripts\
  ferry\ferry.py`, an external tool this repo depends on) is the receiving
  counterpart of `ferry email`: it lists mailboxes, searches by subject, and
  downloads matching attachments, read-only (`EXAMINE` + `BODY.PEEK`) unless
  `--mark-seen`. It deliberately knows nothing about wakapi. Everything
  wakapi-specific — archive grouping, the ledger, the POST, the credentials —
  stays in `box/wakatime.lua`, which is also why `wakatime-fetch.py` was deleted
  rather than grown (the IMAP/MIME protocol work is exactly what Python's stdlib
  does and Lua would have to reinvent).
- **Never copy the `.bdb` across.** Nothing in wakatime-cli ever compacts it, so
  the file only grows (the Windows box's is already 4 MiB while empty); past
  1 MiB the copy path is dead. JSON also compresses ~5-20x, so one part carries
  far more heartbeats. Likewise `--print-offline-heartbeats 0` prints **nothing**
  (`Queue.ReadMany` breaks at `len >= limit` before appending) — unlike
  `--sync-offline-activity 0`, 0 is not "all"; pass the real count.
- **The queue is cleared on a successful send, and that is the point.**
  `--print-offline-heartbeats` always dumps the *whole* queue, so leaving it
  would re-send everything next time and grow until the archive exceeded ferry's
  10 MiB prompt (which *cancels* instead of splitting when non-interactive).
  Safe because by then the parts are in the mailbox, and **nothing deletes a
  message until `:WakaPurge` is run** — at every instant the data lives
  somewhere. `--keep-queue` skips it. Corollary: **do not edit while exporting**,
  a heartbeat appended between the dump and the delete goes with it (the script
  warns when a `wakatime-cli` process is running).
- **Deleting the mail is a separate command, `:WakaPurge`, on purpose.** It is
  the only step that gives up the invariant above, so it must be asked for by
  name: `:WakaSync` itself touches nothing but `\Seen`. It hard-deletes via
  `ferry recv --delete` (IMAP `STORE +FLAGS (\Deleted)` then `EXPUNGE` — a
  **server-side** delete, *not* the client's Deleted Items, no undo), guarded
  three ways: it iterates the **ledger**, so an archive whose POST failed is
  never touched; it matches **per archive name**, not the shared
  `subject_filter` (which matches every archive in the folder, including ones
  that have not been uploaded yet); and it asks for confirmation unless `!` is
  given. `:WakaPurge <archive>` narrows it to one.
- **Integrity is checked, not assumed.** `ferry merge` validates the part
  sequence and `ferry unpack` proves the zip CRC, so an MTA that rewrites line
  endings surfaces as `INTEGRITY FAILURE` instead of silently corrupting
  heartbeats (fallback: ferry's `-f text`, base64 in the body). `:WakaSync` is
  read-only on the mailbox until a POST succeeds.
- **Re-uploading is idempotent**: wakapi hashes each heartbeat into a `UNIQUE`
  index (`models.Heartbeat.Hashed`, excluding id/editor/os/machine) and
  `InsertBatch` dedupes. Only heartbeats younger than `heartbeat_max_age` (4320h
  = 180 days) are accepted. `:WakaSync` keeps a ledger
  (`~/wakatime-ferry/state.json`) instead of relying on `\Seen`, because a
  mail-client rule may already mark mail read on arrival — so `ferry recv`
  search by subject, never by `UNSEEN`, and `--force` re-uploads.
- **The upload auth is `Authorization: Basic base64(api_key)` — no trailing
  colon.** `utils.ExtractBearerAuth` base64-decodes whatever follows the scheme
  and uses it verbatim, so the WakaTime convention (`base64("key:")`) 401s.
  `?api_key=<key>` also works and is the quickest manual check.
- **Credentials live outside the repo**: `imap.json` (host/port/user/password/
  mailbox/`subject_filter`, plus optional `ferry`/`staging`/`state_file`).
  `:WakaSync` resolves it via `$WAKATIME_IMAP_CONFIG`, then `./`, then
  `scripts/imap.json`, and passes `-c` on to `ferry recv`, which reads the same
  file. `.gitignore` carries an `imap.json` line purely as a backstop against
  `git add -A` publishing a mailbox password.
- **The upload is a curl process, not a Lua HTTP stack.** `vim.base64`
  (present in 0.13-dev, checked, byte-identical to .NET's) builds the header and
  `vim.system` runs `curl`, so the sync is one async Lua chain and its progress
  lands in a `wakatime://sync` scratch buffer. Nothing about it runs at startup.
- **`ferry email` shells out to the local `mail` binary** (`mail -s <subject> -a
  <file> <to>`), so nothing about SMTP lives in this repo — the credentials are
  the RHEL6 MTA's own configuration. The consequence matters: **a 0 exit from
  `mail` only means the local MTA accepted the message**, not that Exchange
  delivered it or that the Outlook rule ran. A gateway that strips or quarantines
  a 1 MiB attachment still yields exit 0, and the export has already deleted the
  queue by then. That is the one genuine data-loss path in the bridge, and it is
  why a cron-driven export should keep the `.zip` (see "Automation" below) rather
  than deleting both artifacts.
- **Sizing the queue:** ~350 B per heartbeat, but bbolt's key duplicates the entity
  path, so the `.bdb` runs ~1.3-1.4x the raw JSON and never shrinks (high-water mark).
  The CLI's own `heartbeat_rate_limit_seconds` (120s) does **not** drop the extra
  heartbeats that frequent saves produce — it *queues* them. That inflates the file
  but not the totals (durations are computed from gaps).
- `wakatime-cli` is bundled via `scripts/tools.json` (`install: "bin"` →
  `~/.local/bin/wakatime-cli-linux-amd64`, `version: ""` tracks the latest release).
  No `glibc234` wrapper: it is `CGO_ENABLED=0` static and runs on 2.6.32.

## Verification commands

```powershell
# Syntax-check a Lua file (nvim.exe path: C:\Users\yingfangong\local\nvim-win64\bin\nvim.exe)
nvim --headless -c "luafile <file>" -c "qa!"     # exit 0 = ok

# Headless startup sanity (plugins load)
nvim --headless -u "$env:LOCALAPPDATA\nvim\init.lua" -c "lua vim.defer_fn(function() print('ok', require('lazy').stats().loaded); vim.cmd('qa!') end, 4000)"

# LuaLS static check (config aligned with box/lsp.lua globals)
lua-language-server --check="$env:LOCALAPPDATA\nvim" --configpath=<luarc> --check_format=json --check_out_path=<out>
```

For plugin health checks, force-load all plugins first (headless does not fire
`VeryLazy`):

```lua
require("lazy.core.loader").load(vim.tbl_keys(require("lazy.core.config").plugins), { cmd = "health" }, { force = true })
vim.cmd.doautocmd("User VeryLazy")
vim.cmd("checkhealth")
```

## Packaging & offline install

All under `scripts/`. `tools.json` is the single source of truth for every
downloadable asset (nvim, rg, fd, fzf, pandoc, ty, ruff, stylua, node, and
`external` entries clangd/lua-language-server), plus the `npm` package list.

### Windows → RHEL6 bundle

```powershell
# Full bundle: config + data + nvim + tools + parser-sources
powershell -ExecutionPolicy Bypass -File scripts\package.ps1 -Out <outdir> -Proxy http://127.0.0.1:7897

# Config-only bundle (config + data + prebuilt fff .so, NO nvim/tools/parser-sources)
#   -> use --config-only on install
powershell -ExecutionPolicy Bypass -File scripts\package.ps1 -Out <outdir> -Proxy http://127.0.0.1:7897 -ConfigOnly

# Config + parser-sources (rev-incremental parser rebuild, no nvim/tools)
powershell -ExecutionPolicy Bypass -File scripts\package.ps1 -Out <outdir> -Proxy http://127.0.0.1:7897 -WithParsers
```

- Output: `<out>/nvim-bundle-linux-x86_64-<date>[-config|-config-parsers].zip`.
- `config/` is **cloned from the remote** (reproducible; no local working-tree
  junk) — commit + push before packaging.
- `data/` carries only `lazy/` (mason/ and site/ are NOT bundled; the offline
  installer supplies Linux tools).
- Packaging strips `*.dll/exe/cmd/bat` from plugin trees but **keeps `.so`** —
  that's how the prebuilt fff RHEL6 binary survives.
- Download cache: `<out>/.nvim-tool-cache/` (keyed by resolved version).

The packager copies the locally-built RHEL6 fff `.so`
(`scripts/prebuilt/fff/libfff_nvim.so`, gitignored — build it first with
`scripts/build-fff-rhel6.sh`) to `data/lazy/fff/target/release/libfff_nvim.so`
and records `fff-rhel6 glibc2.17 sha256=<hash>` in the manifest. If the prebuilt
is absent it warns and bundles no fff binary. It never downloads anything from
GitHub for fff.

### Install on the target (RHEL6)

```bash
unzip nvim-bundle-linux-x86_64-<date>-<type>.zip -d bundle && cd bundle
# NB: the zip is NOT inside bundle/ — pass a path that actually resolves. The
# script does not depend on cwd (it re-extracts the zip into a temp dir), but it
# `[ -f "$BUNDLE" ]`s the arg as given, so a bare filename fails with
# "bundle not found" when the zip sits one level up.
./config/scripts/install-offline.sh ../nvim-bundle-linux-x86_64-<date>-<type>.zip --update
# config-only bundle:
./config/scripts/install-offline.sh ../nvim-bundle-linux-x86_64-<date>-config.zip --config-only
```

- `install-offline.sh` auto-detects bundle type from contents.
- `--update` = incremental (config replaced w/ backup; data overlay-merged; only
  changed parsers recompiled; state in `~/.nvim-offline-state`).
- `--config-only` = replace config + overlay-merge data, nothing else.
- Online installers: `install.ps1` (Windows), `install.sh` (macOS/Linux/WSL).

### tools.json schema (per entry)

`{ name, version(""=latest), glibc234(bool), source("github-release"|"nodejs"|"external"),
owner, repo, asset_glob, url_template, latest_url, out_file, binary,
install("nvim-dir"|"node"|"bin"|"external"), realpath }` — plus top-level `npm: [...]`.

The packagers also emit a `tools.sh` companion (no JSON parsing on the offline
box); `install-offline.sh` sources it.

## Fixed workflows

### A. Making a config change (local)

1. Identify the file. Plugin behavior → `lua/plugins/<name>.lua`; core vim behavior
   → `lua/core/*.lua`; custom features/patches → `lua/box/*.lua`; LSP → `lua/box/lsp.lua`;
   shared helpers → `lua/box/`.
2. Edit.
3. **Syntax check:** run `luafile <file>` with the Windows nvim (exit 0 = ok). See
   "Verification commands".
4. **Behavioral check (required for anything non-trivial):** write a temp probe
   under `C:\Users\yingfangong\AppData\Local\Temp\opencode\*.lua`, run it headless
   with `-u %LOCALAPPDATA%\nvim\init.lua`, and assert on real output. Don't trust
   that a change "looks right".
5. Start up once headless to confirm plugins still load (see commands).
6. If a plugin was added/removed/updated, `lazy-lock.json` changes — include it.
7. Commit (only when asked) and push. Remote is **SSH** (`git@github.com:...`) —
   works without the HTTP proxy.

### B. Shipping to RHEL6

1. **Commit + push first** — `package.ps1` clones `config/` from the remote, so
   uncommitted edits do NOT ship.
2. Package (from `C:\Users\yingfangong\AppData\Local\nvim`):
   - config + data + prebuilt fff `.so` only → `-ConfigOnly` (smallest; use `--config-only` on install)
   - + parser-sources (parser rev-incremental) → `-WithParsers`
   - full (nvim + tools) → no switch
   Always pass `-Proxy http://127.0.0.1:7897`.
3. Verify the zip before shipping (see "Bundle verification" below).
4. Copy to RHEL6, unzip, run **the bundle's own** `config/scripts/install-offline.sh`
   (`--update` for incremental, `--config-only` for a config-only bundle).
5. After a successful ship, delete the previous bundle from `Downloads` to avoid
   shipping a stale one by mistake.

### C. Investigating plugin health / reports

1. Force-load all plugins (headless never fires `VeryLazy`), fire `User VeryLazy`
   + `VimEnter`, then `:checkhealth [<name>]`, read the `health://` buffer via
   `vim.fn.bufnr("health://")` and write it to a file. Per-plugin reports are the
   reliable way to see warnings.
2. Distinguish **real config bugs** from environment-missing (mason tools, AI CLIs,
   graphics) and **headless false positives** (snacks.dashboard "setup did not run",
   mkdnflow "not activated yet", `vim.lsp` "no active clients", provider
   warnings) — the latter do not appear in interactive use.

## Bundle verification (before shipping)

```powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem
$z="<out>\nvim-bundle-linux-x86_64-<date><suffix>.zip"
$a=[System.IO.Compression.ZipFile]::OpenRead($z)
# 1) expected top-level; 2) fff .so present + size; 3) manifest.txt
$a.Entries | Where-Object { ($_.FullName -split '/').Count -le 2 } | ForEach-Object { $_.FullName }
$a.Entries | Where-Object { $_.FullName -match 'fff/target/release/libfff_nvim' } | ForEach-Object { "$($_.FullName) $($_.Length)" }
# option check on a config file inside the zip, and ELF magic of the .so (7F 45 4C 46)
$a.Dispose()
```

Expected: `-config` bundle has `config/`, `data/`, `lazy-lock.json`, `manifest.txt`,
and `data/lazy/fff/target/release/libfff_nvim.so` (~12.7 MB, ELF
`7F 45 4C 46`) — **no** `nvim/`, `tools/`, `parser-sources/`. `manifest.txt` must
contain `fff-rhel6 glibc2.17 sha256=<hash>`.

## Rebuilding the fff RHEL6 binary

When you bump the `fff` plugin (its commit in `lazy-lock.json` changes), the
prebuilt `.so` must be rebuilt from that same commit, or the Rust ABI won't match
the Lua plugin.

Run `scripts/build-fff-rhel6.sh` on a **Linux host with network** (WSL is fine) —
NOT on RHEL6 (offline, and its rust 1.97 is too new to target glibc 2.17). It:

1. uses a toolchain capable of targeting glibc 2.17 — **rust 1.90.0** (last std
   baseline that links against 2.17) + zig + cargo-zigbuild. If those are already
   on PATH (rustup, the `1.90.0` toolchain, zig, cargo-zigbuild) it reuses them;
   otherwise it bootstraps an isolated env into `~/.fff-build`,
2. fetches fff at `FFF_COMMIT` (edit the var, or pass `FFF_COMMIT=...`); set
   `FFF_SRC=<dir>` to use an existing checkout (no network),
3. builds `cargo zigbuild --release -p fff-nvim --target x86_64-unknown-linux-gnu.2.17`
   **with default features (the ripgrep walker)** — see "zlob does NOT work on 2.17",
4. verifies max versioned `GLIBC_ <= 2.17` **and** that there are no *strong*
   undefined post-2.17 symbols (statx/getrandom/copy_file_range/…), and writes
   `scripts/prebuilt/fff/libfff_nvim.so`.

The result is **gitignored** — it stays local. You must (re)build it before
packaging. Verify it:

```bash
objdump -T scripts/prebuilt/fff/libfff_nvim.so | grep -oE 'GLIBC_[0-9.]+' | sort -uV | tail -1   # <= 2.17
nm -D --undefined-only scripts/prebuilt/fff/libfff_nvim.so | awk '$1=="U"' | grep -E 'statx|getrandom|copy_file_range'   # must be EMPTY (or 'w', weak)
nm -D scripts/prebuilt/fff/libfff_nvim.so | grep luaopen_fff_nvim
```

Note: keep the build's `FFF_COMMIT` in sync with the `fff` entry in
`lazy-lock.json`.

### zlob does NOT work on glibc 2.17 (use the ripgrep walker)

Upstream's prebuilt fff binaries use the `zlob` feature (`--no-default-features
--features zlob`, a Zig SIMD walker/glob engine). **We cannot** on RHEL6:

- zlob requires **zig >= 0.16**; zig 0.16's std (`Io.Threaded`) makes **strong**
  calls to `statx` / `getrandom` / `copy_file_range` (glibc 2.28 / 2.25 / 2.27).
- glibc 2.17 lacks these, so the final `.so` carries *undefined strong* symbols
  and `dlopen` fails at runtime (`undefined symbol: statx`), even though a
  `max GLIBC_` scan still says 2.17 (those refs are unversioned).
- That's exactly why upstream targets glibc **2.31** for its Linux prebuilts.

So the RHEL6 `.so` is built with the **default ripgrep walker** (`cargo zigbuild
… -p fff-nvim` with no `--features`). Keep `FFF_FEATURES` empty. (Functionally
equivalent; only the traversal/glob engine differs, and glob semantics differ
slightly between `ignore`/`globset` and zlob.)

### WSL toolchain (already provisioned)

The Windows-box WSL (`Ubuntu`) is set up for this rebuild — `~/.profile` puts both
on PATH:

- **rustup** at `~/.cargo/bin` with toolchains **1.90.0** (for fff) and **1.97.0**
  (default, matches the system). Switch with `rustup run 1.90.0 …`,
  `cargo +1.90.0 …`, `RUSTUP_TOOLCHAIN=1.90.0 …`, or `rustup default 1.90.0`.
- **zig 0.16.0** at `~/.local/bin/zig` (→ `~/.local/opt/zig-0.16.0`).
- **cargo-zigbuild** at `~/.cargo/bin/cargo-zigbuild`.
- **libclang** via the PyPI wheel (`pip3 install --user --break-system-packages
  libclang`) — only needed if you ever build the `zlob` feature.

WSL2 reaches the internet directly (no proxy needed for rustup/crates.io/ziglang;
GitHub TLS occasionally flakes — the script retries, and `FFF_SRC=<local checkout>`
skips the fetch entirely). With this in place, a rebuild is just
`bash scripts/build-fff-rhel6.sh`. Verified end-to-end: 1.90 + zig 0.16 +
cargo-zigbuild produce an ELF with max `GLIBC_ 2.17` and no bad undefined refs.

## Pitfalls / gotchas

### Shell & tooling (this Windows box)

- **Never `cd` inside a command** — pass the `workdir` parameter to the shell tool.
- **PowerShell reserves `<` / `>`** — single-quote any regex containing them
  (e.g. `rg -n 'Indent|<Tab>' file`), or the shell errors.
- **Invoke nvim with the call operator** (path has no spaces but be explicit):
  `& "C:\Users\yingfangong\local\nvim-win64\bin\nvim.exe" ...`.
- **Grep/console output sometimes mangles tokens** (e.g. `skip`→`n`, `<Tab>`→`n`,
  `empty`/`help`/`child`→`n`). This is an output-rendering artifact, NOT the file
  content. When a search result looks wrong, open the file with the **Read** tool.
- **`Lazy load all` / `:Lazy` opens the UI and can hang headless** — never use it in
  probes. Use the loader API:
  `require("lazy.core.loader").load(vim.tbl_keys(require("lazy.core.config").plugins), { cmd="..." }, { force=true })`.
- **`:Lazy clean` on this box removes `yazi.nvim`** — its spec is
  `enabled = vim.fn.executable("yazi") == 1` and yazi isn't installed on Windows, so
  lazy treats it as unused; but the RHEL6 bundle ships `data/lazy/`, so restore it at
  the locked commit before packaging:
  `git clone --filter=blob:none https://github.com/mikavilpas/yazi.nvim "$env:LOCALAPPDATA\nvim-data\lazy\yazi.nvim"`
  (add `-c http.proxy=http://127.0.0.1:7897` if needed) then
  `git -C <dir> checkout <commit from lazy-lock.json>`.
- **`nvim --headless` doesn't fire `VeryLazy`/`VimEnter`** — call
  `vim.cmd.doautocmd("User VeryLazy")` and `vim.cmd.doautocmd("VimEnter")` in probes.
  Some probes (esp. `:normal! <C-i>`) can hang headless — always add a hard
  `vim.defer_fn(function() vim.cmd("qa!") end, N)` guard and a shell timeout.
- **cursortab's daemon inherits nvim's stdio and outlives it**, so a probe that
  wraps nvim in `timeout ... nvim --headless ... > file` HANGS even after nvim
  has exited: the shell waits on the pipe the daemon still holds. Give the
  probe an internal `vim.defer_fn(function() vim.cmd('qa!') end, N)` failsafe,
  read `stdpath()` with `nvim --clean` (skips this config, so never spawns the
  daemon), and syntax-check with `--clean` too — `nvim --headless -c 'luafile
  x.lua'` loads the WHOLE config, runs `lazy.setup`, and starts the daemon.
- **Never `pkill -f server/cursortab` to clean up a probe.** The daemon is
  per-user and long-lived; that pattern kills the interactive session's daemon
  too, and the symptom is silent — predictions just stop, `vim.g.cursortab_state`
  sits at `Idle`, and the daemon log's last line is an *earlier* PID than the
  one you expect. Recover with `:CursortabRestart`. Orphans from a probe
  self-terminate (`no clients connected for timeout period, shutting down
  daemon`), so leave them alone.
- **After force-loading the plugins, `print` stops reaching stdout in a headless
  probe** — it prints fine up to that point, then goes nowhere once the event
  loop is pumped (`vim.wait`). The script keeps running (exit 0, no error), so
  this reads as "no output / no failures". Write probe results with
  `io.open(path, "w")` + `:flush()` instead of `print` whenever the probe pumps
  the loop. `vim.wait(ms, function() return false end)` is exactly what a probe
  needs to pump, though: anything a `ColorScheme` handler defers with
  `vim.schedule` (e.g. `box_picker_hl`) has NOT landed yet right after
  `:colorscheme` returns, so assert after a wait or the check silently reads the
  pre-theme value. (Same reason a probe that never pumps sees stale state.)
- **`nvim_feedkeys(..., "nx")` disables remapping** — use `"mt"` when you want to
  test keymaps.
- **`:checkhealth` is synchronous** and writes to a buffer named `health://`; grab it
  right after the `vim.cmd("checkhealth")` call.
- **Staging only part of a file needs LF and hunks kept whole.** When unrelated
  WIP sits in a tracked file (e.g. `AGENTS.md`), the way to commit only your own
  edits is: `git diff -- <file> > p.patch` in the shell, drop the other hunks,
  then `git apply --cached p.patch` — it patches the INDEX, which is at HEAD, so
  the staged blob becomes HEAD + your hunks. Two traps, both hit doing this:
  - **`Set-Content` rewrites the patch with CRLF** (git wrote it with LF), so
    every context line gains a `\r` and git reports the misleading
    `patch does not apply` — it is the line endings, not the context. Write it
    with .NET instead: `[System.IO.File]::WriteAllText($p, ($lines -join
    [char]10) + [char]10, [System.Text.UTF8Encoding]::new($false))`.
  - **A hunk's `@@` header must travel with its own body.** A keep/drop filter
    that bumps the hunk counter *after* the add decision attaches each header to
    the previous hunk — git then reports `corrupt patch`, because the header's
    line counts don't match what follows. Group the lines per hunk first, then
    emit the whole groups.
- **git global proxy is left set** by `package.ps1` (`git config --global http.proxy`).
  Push uses SSH so it's unaffected; if git-over-HTTPS misbehaves, `git config --global --unset http.proxy`.
- **Proxy for downloads/API:** `http://127.0.0.1:7897`. PowerShell
  `Invoke-WebRequest` ignores `HTTP_PROXY` env — pass `-Proxy` explicitly (the
  packagers do). `curl.exe`/`git.exe`/`gh` honor the env vars (`HTTP_PROXY`/`HTTPS_PROXY`).

### Editing config

- **`vim.g.fff` is fff's setup OUTPUT, not config** — configure fff via
  `opts = { ... }` in `plugins/fff.lua` (`require("fff").setup(opts)`).
- **Adding a new global** used in Lua (e.g. `Snacks`) → add it to
  `Lua.diagnostics.globals` in `box/lsp.lua`; otherwise LuaLS reports
  `Undefined global`.
- **Blink/lualine/etc. `version` pins**: blink is pinned `1.*` (v2.0 is on `main`,
  unreleased) — don't bump casually.
- **Never branch on nvim version for RHEL6** — same 0.13-dev. Only branch on
  `vim.g.is_rhel6` for genuine glibc/tool availability.
- **`lua/box/sticky.lua` is broken and unreferenced** (pre-existing syntax errors;
  LuaLS reports them on every check). Nothing requires it — fix or delete it rather
  than treating those diagnostics as new.

### Terminal key handling

- **`<C-i>` and `<Tab>` are the same byte** (`\t`). Do NOT map `<Tab>` in
  **insert** mode — it would shadow both the built-in jumplist-forward `<C-i>`
  and the tab-out / multistep chains. Windows Terminal does not send
  CSI-u/modifyOtherKeys, so the two cannot be distinguished there. Tab
  navigation uses `gt`/`gT` + `<leader>t*`.
- **Normal-mode `<Tab>` is the one deliberate exception**: a mini.keymap
  multistep whose only step is cursortab's prediction accept/jump
  (`editing.lua`), so the accept reads like VS Code's `Tab` and the
  jump-accept-jump rhythm is Cursor's. It does *not* shadow `<C-i>`:
  mini.keymap's fallback returns the original keycode when no step matches, and
  that was verified to behave identically to a bare `<C-i>` (jumplist forward).
  That fallback is load-bearing twice over — it is what keeps raw `<Tab>` safe
  when the daemon is down and no prediction is showing. Remember it before
  adding a second step; the raw key is what makes this mapping safe.

### fff (engine + index)

- fff is a **single-global-root** index; `change_indexing_directory` replaces and
  rescans. Multi-root is unsupported (verified in upstream source).
- On RHEL6 fff uses a **self-built glibc-2.17 `.so`** shipped in the bundle
  (`scripts/prebuilt/fff/libfff_nvim.so`). It must match the fff plugin commit —
  rebuild via `scripts/build-fff-rhel6.sh` whenever the plugin is bumped. Never
  ship upstream's gnu (needs 2.31) or musl (dynamic-musl) builds.
- `fff.rust.health_check()` runs a git discover on every call (uncached in Rust);
  `snacks.lua` caches only the *ready* result (2 s TTL) — while the index is warming
  up the poll loop calls it each iteration.
- fff's async finder retries run in a **fast-event context**; `vim.fn`/`uv` calls
  (`fff_norm`) are unsafe there, so each retry hops back via `async:schedule`
  (already done in the poll loop). The project root is no longer looked up in the
  finder — it's captured at pick time into `opts.fff_root`.
- **Do NOT "optimize" fff to one fixed common root** (`/proj/crane/wa/$USER`).
  That parent is **NFS** (~108k files across ~20 projects); a single root would
  force a full-network rescan on every startup and a watcher over 108k NFS entries
  (unreliable + heavy). The current per-project root + on-demand re-scan is
  intentional. (Investigated and rejected; see the shared-root discussion.)

### Packaging

- `package.ps1` strips `*.dll/exe/cmd/bat` from plugin trees but **keeps `.so`** —
  that's how the prebuilt fff RHEL6 binary survives; don't add a broad `*.so` strip.
- `-ConfigOnly` and `-WithParsers` are mutually exclusive.
- Non-interactive stdin auto-confirms every `[Y/n]` prompt (defaults to yes).
- The download cache (`<out>/.nvim-tool-cache/`) and `versions.json` persist in
  `Downloads`; the cache is keyed by resolved version.
- `config/` in the bundle is the **remote clone**, so run the packager only after
  `git push`.
- The packagers run under `$ErrorActionPreference="Stop"`, which turns native
  commands' stderr (git/npm) into terminating errors — keep git/npm calls wrapped
  in try/catch (the scripts already do).

### RHEL6 runtime

- Hardcoded paths must remain `/home/yingfangong/...`: `~/.local/glibc-2.34`,
  `~/.local/bin`, `~/.local/glibc234/{clangd,lua-language-server}`.
- Never export `LD_LIBRARY_PATH` on RHEL6 (glibc wrappers strip it explicitly).
- Node pinned to **v18.20.4** (patchelf recipe targets that build).
- fff + treesitter trees sit behind NFS/symlinks; `follow_symlinks = true` is required.

## Commit / change hygiene

- Only commit when asked. Keep messages concise and scoped; match existing style
  (`fix:` / `feat:` / `chore:` / `refactor:` prefixes are used).
- Commit `lazy-lock.json` with plugin changes.
- Keep generated/bundle artifacts out of the repo (they live in `Downloads`/out dirs).

## Agent skills

### Issue tracker

Issues and specs live as markdown files under `.scratch/`. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical triage roles, using their default names. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.
