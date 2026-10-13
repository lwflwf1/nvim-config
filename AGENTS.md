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
                          theme (+<leader>uC), hl (groups the colorschemes don't
                          define), picker_hl (snacks picker window bg patch),
                          tools (:ToolInstall), neovide, battery,
                          fff_picker (snacks patch), notifier_anim (snacks patch),
                          tabout (TabOut-rules engine for the smart multistep
                          Tab/S-Tab; chains declared in plugins/editing.lua),
                          sticky (WIP), orgmode_profiles, wakatime (:WakaExport/:WakaSync)
  async.lua               compat shim: async.lua -> promise-async -> async.nvim
  snippets/               LuaSnip snippets
after/
  ftplugin/               per-filetype overrides (systemverilog, log, markdown, ralf, tc, bigfile)
  queries/systemverilog/  context.scm
  syntax/                 ralf.vim, tc.vim
queries/systemverilog/    aerial, function_*, variables (the rest come from the SV fork)
scripts/                  installers + packagers + tools.json
  build-fff-rhel6.sh      cross-build fff's backend for glibc 2.17 (run on Linux/WSL)
  wakatime-export.sh      RHEL6: dump the queue, pack+mail it via ferry (see below)
  wakatime-fetch.py       networked box: fetch mailed archives, verify, upload (IMAP)
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

- **RHEL6 guards:** `vim.g.is_rhel6` disables avante, minuet, snacks.scroll, and
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
- **Minuet / OpenCode Go** (`plugins/minuet.lua` + `plugins/blink.lua`): the key is
  read from opencode's own auth file, whose location is **per-OS** —
  `~/.local/share/opencode/auth.json` on Windows *and* Linux (verified on this box;
  `%LOCALAPPDATA%/opencode` does not exist), `~/Library/Application
  Support/opencode/auth.json` on macOS. The lookup tries both, then
  `OPENCODE_GO_API_KEY`; with no key minuet reports `is_available() == false`, the
  blink source is dropped and the backend never invokes its callback (a headless
  probe then hangs instead of erroring). The `/go` endpoint 401s
  (`MissingSessionID`) without `x-opencode-session`, which is added via
  `provider_options.openai_compatible.transform` — not via curl args.
- **`request_timeout` is curl's `--max-time` for the whole request**
  (`utils.make_curl_args`), streaming included, so it must cover first-token latency.
  Through this box's local proxy `glm-5.3-flash` measures 2.0-2.8s (cold ~5s), which
  is why the budget is 6s and blink's minuet `timeout_ms` must match it; a tighter
  budget silently returns nothing. HTTP/2 through the same proxy stalls ~15s now and
  then (curl exits 000), so `curl_extra_args = { "--http1.1", "--connect-timeout", "5" }`
  is set at minuet's **root** config (`curl_extra_args` is read from
  `require("minuet").config`, not from `provider_options`). Both are plain curl
  options, safe on every platform, and minuet is disabled on RHEL6 anyway. AI is
  manual + per-buffer on purpose (`blink.enable_auto_complete = false`,
  `virtualtext.auto_trigger_ft = {}`, `<leader>ua` arms the buffer) so the source and
  the ghost text never each send a request per typing pause.
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
  aerial's extra SymbolKind groups, `DropBar{Kind,IconKind}Task{,NC}`, and the
  `@org.keyword.face.*` / `@org.agenda.*` faces. Reasons, all verified:
  - **A compiled colorscheme opens with `hi clear`, which drops EVERYTHING set
    outside it — including `default = true` groups.** So a one-shot
    `nvim_set_hl` in a plugin's `config()` (aerial's, gitsigns' staged links)
    is silently lost after `<leader>uC` switches themes. That is why the old
    per-plugin copies needed their own `ColorScheme` autocmd (dropbar's,
    orgmode's) — they are gone, `box_hl` does it for all of them.
  - **`link` combines with attributes**: `{ link = "DiagnosticError", bold = true }`
    takes `bold` from the table and falls back to the link for `fg`. So the
    orgmode faces are links to the theme's semantic groups instead of baking
    `fg()` values.
  - **`default = true` loses to a group the owning plugin already declared with
    `hi default`** — which is why the `@org.keyword.face.*` entries omit it
    (orgmode declares those itself) while everything else that no plugin
    touches keeps it.
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
- **Noice suppresses `recording @a`** (`msg_showmode` is `skip`-routed). lualine
  shows a `REC @<reg>` indicator instead, refreshed on `RecordingEnter`/`Leave`
  (`plugins/ui.lua`).
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
  the fade is no longer quantized by the integer width. The target is re-read
  live via `win:win_opts()` and the animation restarts (same id) through the
  `update` wrapper, because the notifier re-lays-out asynchronously (VimResized /
  same-id replace) and a captured target would be written back stale.
- **The fade fades the WHOLE window through ONE mechanism: a window-local
  highlight namespace** (`box/anim/fade.lua`) that redefines every group the
  notification uses — the window groups (`Normal`/`NormalNC` for the text,
  `NormalFloat` for the float background, `FloatBorder`/`FloatTitle`/
  `FloatFooter` for the border ring) and the style's extmark groups (the fancy
  style draws icon/title/separator with extmarks). **Do not "simplify" this back
  to winhl remaps** — an earlier version did that and it silently faded only the
  extmark groups, because of the ns quirk in the next bullet.
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
  pool** and the names are `snacks_notif_fade2_*` — never reuse a namespace name
  that ever held different group definitions (stale definitions take precedence
  and silently break colors).
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
- **Windows timer resolution caps the animation** (`box/anim/init.lua`): the
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
  does read from the environment). `hide_project_folder` is on so only
  project-relative paths are sent; `sync_ai_disabled` is set on RHEL6 only.
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
  - Networked box: `:WakaSync` (`scripts/wakatime-fetch.py sync`, `ssh` not
    needed) — IMAP fetch of the parts → `ferry merge` → `ferry unpack` → POST to
    `<api_url>/users/current/heartbeats.bulk`.
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
  Safe because by then the parts are in the mailbox, and the receiver does not
  delete a message until the upload succeeded — at every instant the data lives
  somewhere. `--keep-queue` skips it. Corollary: **do not edit while exporting**,
  a heartbeat appended between the dump and the delete goes with it (the script
  warns when a `wakatime-cli` process is running).
- **Integrity is checked, not assumed.** `ferry merge` validates the part
  sequence and `ferry unpack` proves the zip CRC, so an MTA that rewrites line
  endings surfaces as `INTEGRITY FAILURE` instead of silently corrupting
  heartbeats (fallback: ferry's `-f text`, base64 in the body). `wakatime-fetch.py`
  is **read-only until the POST succeeds** (`EXAMINE` + `BODY.PEEK`).
- **Re-uploading is idempotent**: wakapi hashes each heartbeat into a `UNIQUE`
  index (`models.Heartbeat.Hashed`, excluding id/editor/os/machine) and
  `InsertBatch` dedupes. Only heartbeats younger than `heartbeat_max_age` (4320h
  = 180 days) are accepted. `sync` keeps a ledger
  (`~/wakatime-ferry/state.json`) instead of relying on `\Seen`, because a
  mail-client rule may already mark mail read on arrival — so `scan`/`fetch`
  search by subject, never by `UNSEEN`, and `--force` re-uploads.
- **The upload auth is `Authorization: Basic base64(api_key)` — no trailing
  colon.** `utils.ExtractBearerAuth` base64-decodes whatever follows the scheme
  and uses it verbatim, so the WakaTime convention (`base64("key:")`) 401s.
  `?api_key=<key>` also works and is the quickest manual check.
- **Credentials live outside the repo** (`scripts/wakatime-fetch.py` reads
  `imap.json`, searched via `-c`, then `./`, then its own dir; `:WakaSync` passes
  `-c $WAKATIME_IMAP_CONFIG`). `.gitignore` carries an `imap.json` line purely as
  a backstop against `git add -A` publishing a mailbox password.
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

- **`<C-i>` and `<Tab>` are the same byte** (`\t`). Do NOT map `<Tab>` in normal
  mode — it shadows the built-in jumplist-forward `<C-i>`. Windows Terminal does
  not send CSI-u/modifyOtherKeys, so the two cannot be distinguished there.
  Tab navigation uses `gt`/`gT` + `<leader>t*`.

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
