# Next Steps

The working prototype renders the reference Markdown documents with the user's Neovim appearance.
Preserve that behavior while improving portability and preview latency.

Reviewed: 2026-10-31

## Portability and repeatable validation

- [x] (p1) [refactor] Replace hardcoded editor, theme, plugin, and parser paths with explicit configuration and sensible defaults.
- [x] (p2) [feature] Provide a sample appearance profile so another user can run the tool without this personal Neovim setup.
- [x] (p1) [chore] Declare runtime and development dependencies; provide a reproducible installation method.
- [ ] (p1) [test] Turn the historical harnesses into tests that resolve paths from the checkout and use temporary output directories.
- [ ] (p2) [test] Add self-contained fixtures for Markdown structures, all supported code languages, aliases, Unicode, and long lines.
- [ ] (p2) [test] Retain checks for complete-document tails, stdin, unusual filenames, modelines, cancellation, and source immutability.
- [ ] (p2) [test] Exercise parser/query mismatches and missing dependencies with actionable errors.
- [ ] (p2) [test] Test released Neovim versions and declare the supported minimum.
- [ ] **Landlock allows writes to all of /tmp.** (p3) [refactor] `readonly.py` grants full write rights on
  `/tmp` rather than only the per-run `mdpreview-*` directory; scope the rule to that directory.
- [ ] (p2) [docs] Document the Linux/Landlock requirement and remove experiment-only helper entrypoints.

## CLI and fzf integration

- [x] **Large tables hang rendering: `mdpreview SYNTAX.md` times out.** (p1) [bug] Two causes, both fixed for
  viewports: Neovim's `conceal_lines` hook (dropped from the Markdown highlights query in `profile.lua`) and
  render-markdown's debounce dropping the post-resize update (`config.debounce = 0`).
- [x] **Complete output of very large tables is still too slow.** (p1) [perf] Mitigated: two forced redraws
  removed and the grid pre-sized (2-3x faster), and output over `--budget` falls back to bat. The underlying
  cost is in Neovim (rows x injected trees); see the two items below.
- [ ] **Patch the Tree-sitter highlighter at runtime.** (p3) [perf] In `profile.lua`, wrap
  `TSHighlighter`'s per-line path (`for_each_highlight_state` from `on_range_impl`) with a row-indexed lookup
  of tree root ranges built once per `on_win`, so each line visits only intersecting trees. Would let
  `SYNTAX.md`-sized tables render instead of falling back. Fragile: private internals of a dev build, so
  feature-detect the fields, keep the unpatched path as fallback, and add a test that fails loudly when the
  internals change. Prefer the upstream fix if it lands.
- [ ] **File the Neovim issue.** (p2) [chore] Draft and `nvim --clean` repro in
  `docs/upstream/neovim-treesitter-injection-cost.md`. Needs `gh auth login`; search for duplicates first,
  then link the issue here and drop the workaround notes once fixed upstream.
- [ ] **Non-numeric fzf size variables give a raw ValueError.** (p3) [bug] `int(os.environ["FZF_PREVIEW_COLUMNS"])`
  in `mdpreview` main() prints `invalid literal for int()`; report which variable was bad instead.
- [ ] (p2) [feature] Add `--version` and keep its output consistent with the release tag.
- [ ] (p3) [docs] Provide a checked-in mixed-file fzf integration example with bat fallback and resize refresh.
- [ ] (p2) [test] Verify Markdown aliases, uppercase extensions, symlinks, empty files, and renderer failures.
- [ ] (p2) [bug] Review selection parsing for filenames containing literal pipes or display separators.
- [ ] (p2) [docs] Clarify full-document versus viewport behavior and how scrolling interacts with each mode.
- [ ] (p2) [feature] Define readable fallbacks for input, row, and timeout limits.

## Replacing nvimpager

- [ ] **Replace nvimpager uses and aliases with mdpreview.** (p2) [chore] Depends on paging mode below.
  `~/.shell/aliases/nvimpager.sh` defines `nvimpager` (wrapper), `vimcat`/`vc`, `vimpage`, `vimtail`/`vt`
  (`vt.nvim-log`, `vt.syslog`, ...), `vc.syn FT`, and `vc.tmux-keys` (stdin with `ft=tmux`). Other callers:
  `~/.shell/scripts/{vim-fzf-preview.sh,bat-list-preview,grc-list}`, `~/.shell/scripts/tools/vim-preview/`,
  `~/.shell/zsh/{functions.zsh,plugin-configs/fzf-tab.zsh}`, `~/.shell/aliases/programs/hyperfine.sh`, and
  tmux (`conf.d/{patterns,tools}.conf`, `scripts/{viewer,nvim-layout}.sh`; `@pattern_nvimpager` pane
  detection must match the new command name). Then drop the deploy recipe
  (`~/.shell/deploy/recipes/nvimpager.sh`, `catalog.tsv`). Mapping: `-l/--language` -> `--filetype`,
  `-c` -> cat mode, `-p` -> paging mode. Gap: `-t/--tail` (follow a growing log) has no equivalent; decide
  whether mdpreview gets a follow mode or `vimtail` stays on nvimpager.
- [x] **Add a paging mode through less.** (p2) [feature] Render the complete document (as `--all` does) and pipe
  it into `${MDPREVIEW_PAGER:-less -R}`; respect `$LESS`, and keep wide glyphs and RGB sequences intact.
  Output over the 4,096-row limit should fall back to a clear error rather than a truncated page.
- [ ] **Embedded Neovim pager.** (p3) [feature] Later alternative to less: attach the terminal to the embedded
  Neovim with the same profile, read-only, giving Neovim search, live render-markdown, and re-wrap on resize
  (closest to nvimpager `-p`). Needs a TUI attach path beside the screen-grab RPC loop and quit keys; would
  also enable a tail/follow mode (`:checktime` timer) to replace `vimtail`.
- [x] **Auto paging by default.** (p2) [feature] Decided: `--paging=auto|always|never` (matching bat), default
  `auto`: page with less when stdout is a terminal and the render is taller than the screen, otherwise cat.
  Treat `$FZF_PREVIEW_COLUMNS`/`LINES` and a `$NVIM` parent (Neovim terminal buffers, where Telescope's
  previewer gives the command a real TTY) as cat. `mdpreview-dispatch` keeps forcing cat output.

## Performance

- [x] **Track Markdown benchmark averages.** (p2) [perf] `benchmarks/run` records small/medium/large/code samples
  in `benchmarks/history.tsv` and updates the SYNTAX.md table; run it after every change.
- [ ] **Benchmark render time per filetype.** (p2) [perf] Time every `filetypes.json` entry with hyperfine (fixture
  plus a larger realistic file each): Tree-sitter vs regex syntax, `--all` vs a viewport, against bat on the
  same file, and the dispatch overhead. Rough one-off timings on 2026-10-31 at 80 columns: most filetypes
  100-350 ms, markdown about 530 ms, astro about 710 ms, cuda about 950 ms (likely parser or injection
  loading). Record results in a doc and add a check that flags regressions. Also: a plain 5,000-line list
  takes over 8 s at the 4,096-row grid even without tables, so tall grids are slow in their own right.
- [ ] **grid_scroll copies the whole grid.** (p3) [perf] `Renderer.event` deep-copies every row on each
  `grid_scroll`, O(rows x columns) per scroll; at 4,096 rows this adds up. Copy only the scrolled region.
- [ ] (p2) [perf] Measure startup, first usable fzf content, total render time, and peak memory on representative documents.
- [ ] (p3) [perf] Separate warm-process results from fresh-process measurements and rendered-output cache hits.
- [ ] (p2) [perf] Profile before optimizing; identify theme loading, parser loading, rendering, and RPC costs separately.
- [ ] (p3) [perf] Trial an optional persistent Neovim worker if startup dominates, with cancellation and cleanup tests.
- [ ] (p3) [perf] Add caching only if measurements justify it; include viewport, file content, theme, configuration, and parser versions.

## Rendering fidelity and larger documents

- [ ] (p3) [test] Compare all reference features at multiple widths, including footnotes, wiki links, HTML comments, and code labels.
- [ ] (p3) [test] Qualify transparent backgrounds, combining characters, emoji, and wide glyphs in more terminal/font combinations.
- [ ] (p3) [feature] Preserve additional underline attributes and assess terminal hyperlink support.
- [ ] (p3) [feature] Investigate complete-document export beyond one enlarged grid without duplicating or skipping virtual rows.
- [ ] (p2) [docs] Define memory and parsing limits before claiming streaming or large-file support.

## Releases

- [x] **No version file.** (p2) [chore] The version exists only as tag `v0.1.0` and README text. Add a
  top-level `VERSION` (and have `--version` read it) so bumps have one source of truth.
- [ ] (p2) [chore] Follow the SemVer and annotated-tag process in [docs/RELEASING.md](docs/RELEASING.md).
- [ ] (p2) [docs] Record user-visible changes and known limitations in [CHANGELOG.md](CHANGELOG.md).
- [ ] (p2) [test] Run the portable integration suite before each release once it is available.

## Optional support for other filetypes

- [ ] **SYNTAX.md has no regeneration script.** (p3) [chore] The Neovim-vs-bat comparison in `SYNTAX.md`
  was produced by an ad hoc Lua/Python scan plus hand review of extension collisions. Check in a script
  (e.g. `scripts/syntax-coverage`) with the collision overrides so the list can be refreshed when parsers
  or bat change.
- [x] (p3) [feature] Evaluate whether Neovim-specific source rendering adds value beyond the current bat integration.
- [x] (p3) [feature] If needed, add filetype detection or `--filetype`, on-demand parsers, and a general render-ready signal.
- [ ] (p3) [perf] Compare startup, parsing time, and memory against the Markdown-only profile before enabling broader support.
- [x] **systemd entry is unreachable through dispatch.** (p3) [feature] bat's INI syntax claims `*.service`,
  `*.timer` and the other unit extensions, so `gen-dispatch` sends them to bat. Neovim's systemd syntax is
  more specific; set `"prefer_over_bat": true` on the entry in `filetypes.json` if it should win.
- [ ] **Rename the project now that it is not Markdown-only.** (p3) [chore] `mdpreview` renders ~40 filetypes.
  Candidates: `nvcat` (short, "cat through Neovim"), `nvim-cat` (matches the `nvim-md-cat` repo name),
  `nvpreview`, `vimprint`, `screencat` (describes the grid capture). Renaming touches the executable,
  `mdpreview-dispatch`, the `mdpreview_ready` RPC event, the `_G.mdpreview` Lua module, the temp-dir prefix,
  docs, and the PATH links; keep an `mdpreview` symlink for one release.
- [ ] **Dispatch carries machine-specific paths.** (p3) [chore] `mdpreview-dispatch` embeds bat's version and
  `--map-syntax`/home-directory globs from this machine's bat config; another machine must run
  `./gen-dispatch`, and `tests/dispatch.bats` fails until it does.
- [ ] **Render tests depend on this machine's Neovim setup.** (p2) [test] `tests/render.bats` needs the
  personal parsers and theme; skip it with a clear message when `find_paths()` reports missing dependencies.
