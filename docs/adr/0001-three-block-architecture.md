# ADR 0001: Three-block architecture with the `box` personal module

Date: 2026-10-10
Status: accepted

## Context

Custom code was scattered across `lua/core/`, `lua/config/`, `lua/util/`,
`lua/project/`, `lua/` root files and plugin specs. Boundaries were unclear:
`core/keymaps.lua` depended on personal helpers, plugin patches lived in
`config/`, and there was no single place for "my own stuff".

## Decision

1. **Three blocks:**
   - `lua/core/` — plain Neovim config (options/keymaps/autocmds), no custom deps.
   - `lua/plugins/` — lazy.nvim specs.
   - `lua/box/` — everything custom: features, plugin patches, misc
     (mini/snacks style: one submodule per concern, each with its own doc header).
2. **`box` loading:** `require("box").setup()` early (keymaps/autocmds/commands,
   before `lazy.setup`) and `require("box").setup_late()` after lazy
   (theme/LSP/tools that need plugin rtp).
3. **Dependency direction:** `core/` must not require `box`; specs may
   `require("box.*")` (patches by nature). Patches (`fff_picker`,
   `notifier_anim`) are imported by the snacks spec.
4. **rtp contracts stay put:** `after/`, `queries/`, `ginit.vim`, and the
   `lua/async.lua` compat shim (a require path plugins resolve).
5. `lua/snippets/` stays a path-loaded data dir (LuaSnip `paths`).

## Consequences

- Adding a feature = one file in `lua/box/` that registers its own keymaps.
- `box` wins rtp precedence over any future plugin providing `lua/box/` —
  re-check on plugin additions (rename is mechanical if it ever happens).
- RHEL6 bundle packaging is unaffected (everything lives inside `config/`).
