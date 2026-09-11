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
  core/                   options.lua, keymaps.lua, autocmds.lua   (plain vim config)
  config/                 lsp.lua, project.lua, parsers.lua       (infrastructure)
  util/                   tools.lua  (:ToolInstall / :ToolUpdate)
  plugins/                one file per plugin (lazy spec) — THE import dir
  async.lua               compat shim: async.lua -> promise-async -> async.nvim
  orgmode-profiles.lua    personal/work org profile switcher
  snippets/               LuaSnip snippets
after/
  ftplugin/               per-filetype overrides (systemverilog, log, markdown, ralf, tc, bigfile)
  queries/systemverilog/  context.scm, textobjects.scm
  syntax/                 ralf.vim, tc.vim
queries/systemverilog/    aerial, highlights, textobjects, function_*, variables
scripts/                  installers + packagers + tools.json
  build-fff-rhel6.sh      cross-build fff's backend for glibc 2.17 (run on Linux/WSL)
  prebuilt/fff/           GENERATED (gitignored): RHEL6 libfff_nvim.so, built by build-fff-rhel6.sh
.opencode-memory/         local agent session memory (gitignored)
```

## Startup flow (`init.lua`)

1. Set `vim.g.os` from `vim.uv.os_uname()`; on Linux compute `vim.g.is_rhel6`
   (kernel `2.6.32` or glibc `< 2.18`) and `vim.g.glibc_version`.
2. Windows: set clipboard to `win32yank`, set proxy env (`127.0.0.1:7897`), extend PATH.
3. `require("core.options")`, `core.keymaps`, `core.autocmds`, `config.project`.
4. Bootstrap `lazy.nvim` (clones if missing) and `require("lazy").setup({ spec = { { import = "plugins" } } })`.
5. `require("config.lsp").setup()` and `require("util.tools")`.

**Important:** `lazy.setup` uses `spec = { import = "plugins" }` — every Lua file
under `lua/plugins/` is treated as a lazy plugin spec. Files at `lua/` root
(e.g. `async.lua`, `orgmode-profiles.lua`) are NOT plugin specs.

## Conventions

- **Leader** = `<Space>` (`core/keymaps.lua`).
- Each plugin = one file in `lua/plugins/`, returning a lazy spec table.
- Prefer `opts = {}` over `config = function()` when the plugin follows the
  lazy.nvim convention; use `config` only when extra wiring is needed.
- Use `vim.tbl_extend`/`vim.tbl_deep_extend` and guard optional plugin loads with
  `pcall(require, ...)`.
- Keep comments concise and explain *why* (non-obvious decisions), not *what*.
- LuaLS is configured with `diagnostics.globals = { "vim", "Snacks" }`
  (`config/lsp.lua`); keep `lua_ls` clean (`lua-language-server --check`, see below).

## Non-obvious design decisions (do not "fix" without reading the comment)

- **RHEL6 guards:** `vim.g.is_rhel6` disables avante, minuet, snacks.scroll, and
  forces blink.cmp's fuzzy to the pure-Lua implementation (the prebuilt Rust fuzzy
  lib needs glibc ≥ 2.18). **RHEL6 nvim is kept on the same version as Windows
  (both 0.13-dev)** — do NOT add version-branch shims for "older nvim"; only branch
  on `is_rhel6` for real glibc/tooling matters.
- **FFF engine** (`plugins/fff.lua` + `plugins/fzf.lua`): `ff/fz/fw` and
  `fn/fo` are snacks.picker sources backed by fff's Rust index (programmatic API),
  not fff's bundled UI. `fff.nvim` is a **single-global-root** index (no multi-root
  support) — `change_indexing_directory` re-roots by replacing + rescanning. RHEL6
  project trees live behind symlinks → `follow_symlinks = true`.
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
- **Noice suppresses `recording @a`** (`msg_showmode` is `skip`-routed). lualine
  shows a `REC @<reg>` indicator instead, refreshed on `RecordingEnter`/`Leave`
  (`plugins/ui.lua`).
- **`glibc234` tools** (node/pandoc/clangd/lua-language-server) on RHEL6 are
  patchelf'd to a glibc-2.34 loader and wrapped to `unset LD_LIBRARY_PATH`
  (see `scripts/install-offline.sh`). Never export `LD_LIBRARY_PATH`.

## Treesitter parsers & the systemverilog fork

- Parser list: `lua/config/parsers.lua` (27 langs).
- `systemverilog` is overridden to the personal fork
  `https://github.com/lwflwf1/tree-sitter-systemverilog` (dynamic `master` tracking)
  in `plugins/treesitter.lua`.
- Custom SV queries live in `queries/systemverilog/` + `after/queries/systemverilog/`.
- `:ToolInstall` installs missing mason tools from `config.lsp` + `plugins/formatter`
  and missing parsers; `:ToolUpdate` refreshes mason registry + parsers.

## Verification commands

```powershell
# Syntax-check a Lua file (nvim.exe path: C:\Users\yingfangong\local\nvim-win64\bin\nvim.exe)
nvim --headless -c "luafile <file>" -c "qa!"     # exit 0 = ok

# Headless startup sanity (plugins load)
nvim --headless -u "$env:LOCALAPPDATA\nvim\init.lua" -c "lua vim.defer_fn(function() print('ok', require('lazy').stats().loaded); vim.cmd('qa!') end, 4000)"

# LuaLS static check (config aligned with config/lsp.lua globals)
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
./config/scripts/install-offline.sh nvim-bundle-linux-x86_64-<date>-<type>.zip --update
# config-only bundle:
./config/scripts/install-offline.sh nvim-bundle-linux-x86_64-<date>-config.zip --config-only
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
   → `lua/core/*.lua`; LSP → `lua/config/lsp.lua`; shared helpers → `lua/config/` or `lua/util/`.
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
   mkdnflow/oil-git "not activated yet", `vim.lsp` "no active clients", provider
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
- **`nvim --headless` doesn't fire `VeryLazy`/`VimEnter`** — call
  `vim.cmd.doautocmd("User VeryLazy")` and `vim.cmd.doautocmd("VimEnter")` in probes.
  Some probes (esp. `:normal! <C-i>`) can hang headless — always add a hard
  `vim.defer_fn(function() vim.cmd("qa!") end, N)` guard and a shell timeout.
- **`nvim_feedkeys(..., "nx")` disables remapping** — use `"mt"` when you want to
  test keymaps.
- **`:checkhealth` is synchronous** and writes to a buffer named `health://`; grab it
  right after the `vim.cmd("checkhealth")` call.
- **git global proxy is left set** by `package.ps1` (`git config --global http.proxy`).
  Push uses SSH so it's unaffected; if git-over-HTTPS misbehaves, `git config --global --unset http.proxy`.
- **Proxy for downloads/API:** `http://127.0.0.1:7897`. PowerShell
  `Invoke-WebRequest` ignores `HTTP_PROXY` env — pass `-Proxy` explicitly (the
  packagers do). `curl.exe`/`git.exe`/`gh` honor the env vars (`HTTP_PROXY`/`HTTPS_PROXY`).

### Editing config

- **`vim.g.fff` is fff's setup OUTPUT, not config** — configure fff via
  `opts = { ... }` in `plugins/fff.lua` (`require("fff").setup(opts)`).
- **Adding a new global** used in Lua (e.g. `Snacks`) → add it to
  `Lua.diagnostics.globals` in `config/lsp.lua`; otherwise LuaLS reports
  `Undefined global`.
- **Blink/lualine/etc. `version` pins**: blink is pinned `1.*` (v2.0 is on `main`,
  unreleased) — don't bump casually.
- **Never branch on nvim version for RHEL6** — same 0.13-dev. Only branch on
  `vim.g.is_rhel6` for genuine glibc/tool availability.

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
- `fff.rust.health_check()` runs a git discover — it's cached in `fzf.lua`
  (2 s TTL); don't call it per keystroke.
- fff's async finder runs in a **fast-event context**: `vim` API calls like
  `nvim_buf_get_name` (via `project_root`) are forbidden there — hop to the main
  thread with `async:schedule` (already done in the poll loop).
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
