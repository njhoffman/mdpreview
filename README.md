# mdpreview

Render Markdown to ANSI terminal output using Neovim, Tree-sitter, and render-markdown.nvim. It also renders
about 40 config and source filetypes that bat has no syntax for, using Tree-sitter or Neovim regex syntax.
The command captures rendered characters and styles, including headings, icons, nested lists, code backgrounds,
and tables. The GitHub repository is named `nvim-md-cat`; the executable is `mdpreview`.

The current version is in [VERSION](VERSION) (`0.5.4`), with a matching annotated Git tag (`v0.5.4`).
See [CHANGELOG.md](CHANGELOG.md), [TODO.md](TODO.md), [SYNTAX.md](SYNTAX.md) (filetype coverage), and the
[release process](docs/RELEASING.md).

## Requirements

Runtime (`make check`, or `mdpreview --check`, verifies these and prints the versions found):

| Dependency | Required | Tested with | Notes |
|---|---|---|---|
| Linux with Landlock | yes | kernel 6.17, ABI 7 | x86-64 |
| Python | yes | 3.13.7 | 3.11 or later (`tomllib`); run as `/usr/bin/python3` |
| msgpack (Python) | yes | 1.0.3 | `apt install python3-msgpack`, or `make deps` (pip, user install) |
| Neovim | yes | v0.13.0-dev-1915+gc5641b2bfb | released versions not yet verified |
| render-markdown.nvim | yes | v8.14.0-2-g8e87953 | any plugin manager; found under `plugin_dirs` |
| mini.icons | no | v0.18.0-5-g9e4c164 | icons need a Nerd Font |
| Tree-sitter parsers | no | | Neovim bundles markdown and markdown_inline; code fences and other filetypes need their parsers |
| bat | no | 0.26.1 | fallback renderer and `mdpreview-dispatch` |
| less | no | 668 | `--paging` (or set `MDPREVIEW_PAGER`) |

Development (`make check-dev`): bats 1.5 or later, `script` (util-linux), fzf, git.

Dependencies are read from an existing installation; no plugin manager runs.

## Install

```sh
make check     # dependencies and resolved configuration
make install   # symlink mdpreview and mdpreview-dispatch into ~/.local/bin (PREFIX=... to change)
make uninstall
```

The commands are linked, not copied: mdpreview finds `profile.lua`, `readonly.py`, `config.py`,
`filetypes.*` and `queries/` next to its real path, so keep the checkout in place. `make test`, `make bench`
and `make dispatch` run the tests, the benchmarks and the dispatch generator.

## Configuration

mdpreview reads `~/.config/mdpreview/config.toml` (or `$MDPREVIEW_CONFIG`); every key is optional and
`MDPREVIEW_<KEY>` environment variables override single keys. See [config.example.toml](config.example.toml).
Without a file it finds plugins in lazy.nvim's and the packpath's directories, uses
`~/.local/share/nvim/site` for parsers when present, Neovim's default colorscheme, and render-markdown's
default options. Point `theme` (a Lua file returning a table with `apply()`, with `lua_path` for its modules)
or `colorscheme`, and `markdown_options` (your editor's render-markdown config file, or a file returning the
options) at an editor setup to match its appearance.

```sh
mdpreview --check   # resolved settings and their sources, versions, warnings; exit 1 if something required is missing
```

Missing optional pieces are skipped with a warning in `--check`; a missing Neovim or render-markdown is an
error.

## Usage

Run from the checkout or after `make install`:

```sh
./mdpreview README.md
./mdpreview --columns 120 README.md
./mdpreview --columns 80 --lines 24 README.md
./mdpreview --start-line 20 --lines 40 README.md
cat README.md | ./mdpreview -
./mdpreview --filetype tmux ~/.tmux.conf
./mdpreview --paging=always README.md
```

### Output modes

mdpreview emits either the **complete document** or one **viewport**:

| | Complete document | Viewport |
|---|---|---|
| Chosen by | `--all`; also the default when none of `--lines`, `--start-line` or `$FZF_PREVIEW_LINES` is given | `--lines N`, `--start-line N`, or `$FZF_PREVIEW_LINES` (fzf previews without `--all`) |
| Rows emitted | every screen row of the rendered document, up to 4,096 | at most the viewport height (`--lines`, else `$FZF_PREVIEW_LINES`, else the terminal height) |
| Time limit | `--budget` (default 5 s), then the bat fallback | `--timeout` per render step only |
| Paging | `--paging=auto` pages it when it is taller than the terminal | never paged; `--paging=always` with `--lines` or `--start-line` is an error |

Both modes load and parse the whole file, but a viewport draws only one screen, so it is faster on longer
documents (see the [benchmarks](SYNTAX.md#markdown-rendering-benchmarks)) and is the safer choice for very
large tables, which can exceed the complete-output budget.

Scrolling works differently in each mode:

- **Complete document.** Scroll in the pager, or in the fzf preview window (mouse, `shift-up`/`shift-down`).
  The output is static: wrapping was done by Neovim at the width given, so resizing needs a fresh render
  (`--bind 'resize:refresh-preview'` in fzf).
- **Viewport.** The output is exactly one screen; scrolling the fzf preview reveals nothing more. To show
  another part, run again with a different `--start-line`. `--start-line` counts **source lines**, not screen
  rows: wrapped lines, rendered tables, and render-markdown's virtual rows (heading padding, code borders)
  take more or fewer screen rows than source lines, so stepping `--start-line` by the viewport height does not
  move by exactly one screen.
- **Jumping to a line in fzf** (for example a grep match): with a viewport, pass the line number as
  `--start-line {2}` so the match is the first row. With the complete document, fzf's `--preview-window
  '+{2}'` offset counts screen rows, so it drifts from the source line wherever rows wrap or are added.

### Paging

`--paging=auto` (the default) pipes the complete document into `$MDPREVIEW_PAGER` (default `less -R`; `$LESS`
applies) when stdout is a terminal and the output is taller than the screen, and prints it otherwise. It
always prints when stdout is piped, for a viewport (`--lines`, `--start-line`), inside fzf previews
(`FZF_PREVIEW_COLUMNS`/`FZF_PREVIEW_LINES` set), and inside Neovim terminal buffers (`$NVIM` set), which
covers Telescope's previewer even though it provides a terminal. `--paging=always` pages even short documents;
`--paging=never` always prints. The pager runs with `LESSHISTFILE=-` because Landlock blocks writes outside
`/tmp`, and with `LESSUTFCHARDEF=e000-f8ff:p,f0000-ffffd:p,100000-10fffd:p` (unless you set your own) so
less shows Nerd Font icons in the Private Use Areas instead of `<U+F0CA3>`. Ctrl-C is left to the pager.

### Budget and fallback

Complete output (the default in a terminal, and `--all`) must finish within `--budget` seconds (default 5;
`0` disables it). Documents that take longer, or exceed 4,096 screen rows, are shown with bat instead
(`--language=markdown` for Markdown, bat's own detection otherwise) with a one-line notice on stderr; the
result is paged like a normal render. `--fallback=none` reports the error instead. Very large Markdown tables
hit this: Neovim's Tree-sitter highlighter does per-line work for every injected tree, and each table cell is
one tree (see [docs/upstream](docs/upstream/neovim-treesitter-injection-cost.md)). `mdpreview-dispatch`
uses `--budget=2` so fzf previews stay responsive.

Install with `make install` (see [Install](#install)).

## fzf

```sh
printf '%s\n' ./*.md |
  fzf --preview 'mdpreview --all {}' \
      --preview-window 'right:75%:nowrap' \
      --bind 'resize:refresh-preview'
```

`--all` emits the complete document for scrolling. Omit it for a single viewport, sized using
`FZF_PREVIEW_COLUMNS` and `FZF_PREVIEW_LINES` (see [Output modes](#output-modes)). Neovim performs wrapping; refreshing on resize recomputes layout.
For a mixed-file preview, use `mdpreview-dispatch`: it sends Markdown and the other filetypes in
[SYNTAX.md](SYNTAX.md) to mdpreview and everything else to bat, and falls back to bat if mdpreview fails:

```sh
fzf --preview 'mdpreview-dispatch {}' --preview-window 'right:75%:nowrap' --bind 'resize:refresh-preview'
mdpreview-dispatch --print path/to/file   # print the filetype; exit 1 when bat would handle it
```

The script is a generated bash `case` (a few milliseconds, no Neovim or Python start-up). Regenerate it with
`./gen-dispatch` after editing [filetypes.json](filetypes.json) or changing bat's syntaxes or `--map-syntax`
config; `tests/dispatch.bats` fails while it is stale. Link it onto PATH like `mdpreview`. See
[development and integration notes](docs/DEVELOPMENT.md).

## Benchmarks

```sh
benchmarks/run            # waits for load <= 0.6 x CPUs, records, updates SYNTAX.md
benchmarks/run --dry-run  # print the table only
```

Renders four generated samples ([benchmarks/](benchmarks/): small, medium, large, and a code-fence-heavy
one; regenerate them with `benchmarks/generate.py`) in complete and viewport mode, appends the medians to
`benchmarks/history.tsv`, and rewrites the comparison table in [SYNTAX.md](SYNTAX.md#markdown-rendering-benchmarks)
against the average of all earlier runs. Run it after every change.

## Tests

```sh
bats tests/
```

`make test` runs the same. Files: `dispatch.bats` (routing, with stub commands), `render.bats` (every table
filetype through the configured Neovim), `paging.bats`, `fallback.bats`, `config.bats`, `robustness.bats`
(tails, viewports, filenames, stdin, modelines, errors, terminal round trip, signal cleanup, immutability,
sandbox), `languages.bats` (code-fence colors), and `fzf.bats` (a real fzf session; skipped without fzf).
Python helpers live in `tests/helpers/`; fixtures in `tests/fixtures/`. Tests that need a configured theme
skip without one.

## Code highlighting

Label fenced blocks with `c`, `cpp`, `rust`, `bash`, `go`, `python`, `javascript`, or `sql`:

````markdown
```rust
let message = "hello";
```
````

Verified aliases include `c++`, `cxx`, `cc`, `sh`, `shell`, `js`, and `py`.
Single-backtick spans retain inline-code styling without identifying a programming language.

## Architecture and limits

Python starts a private embedded Neovim with `profile.lua`, temporary XDG directories, and plugin managers
disabled. The profile loads selected editor settings and parser/query pairs. After render-markdown signals
readiness, Python converts the RGB screen grid into ANSI output and closes Neovim.

`readonly.py` restricts filesystem writes with Linux Landlock. The query extension handles C++ fence labels.
Each invocation starts a new Neovim; there is no persistent worker. Input is limited to 10 MiB, width to
10–500 columns, and complete output to 4,096 screen rows. A viewport still loads the whole input file.

Released-Neovim compatibility remains unverified (see TODO.md).
