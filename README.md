# mdpreview

Render Markdown to ANSI terminal output using Neovim, Tree-sitter, and render-markdown.nvim. It also renders
about 40 config and source filetypes that bat has no syntax for, using Tree-sitter or Neovim regex syntax.
The command captures rendered characters and styles, including headings, icons, nested lists, code backgrounds,
and tables. The GitHub repository is named `nvim-md-cat`; the executable is `mdpreview`.

The current version is in [VERSION](VERSION) (`0.5.0`), with a matching annotated Git tag (`v0.5.0`).
See [CHANGELOG.md](CHANGELOG.md), [TODO.md](TODO.md), [SYNTAX.md](SYNTAX.md) (filetype coverage), and the
[release process](docs/RELEASING.md).

## Requirements

- Linux on x86-64 with Landlock support.
- `/usr/bin/python3` (3.11 or later) with the `msgpack` module.
- A recent Neovim; tested with `v0.13.0-dev-1915+gc5641b2bfb`.
- `render-markdown.nvim`, and optionally `mini.icons` (use a Nerd Font for its icons).

Dependencies are read from an existing installation; no plugin manager runs. Neovim's bundled markdown parsers
are used unless a parser directory with newer ones is configured.

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

Keep `mdpreview`, `profile.lua`, `readonly.py`, `filetypes.py`, `filetypes.json`, and `queries/` together:

```sh
./mdpreview README.md
./mdpreview --columns 120 README.md
./mdpreview --columns 80 --lines 24 README.md
./mdpreview --start-line 20 --lines 40 README.md
cat README.md | ./mdpreview -
./mdpreview --filetype tmux ~/.tmux.conf
./mdpreview --paging=always README.md
```

### Paging

`--paging=auto` (the default) pipes the complete document into `$MDPREVIEW_PAGER` (default `less -R`; `$LESS`
applies) when stdout is a terminal and the output is taller than the screen, and prints it otherwise. It
always prints when stdout is piped, for a viewport (`--lines`, `--start-line`), inside fzf previews
(`FZF_PREVIEW_COLUMNS`/`FZF_PREVIEW_LINES` set), and inside Neovim terminal buffers (`$NVIM` set), which
covers Telescope's previewer even though it provides a terminal. `--paging=always` pages even short documents;
`--paging=never` always prints. The pager runs with `LESSHISTFILE=-` because Landlock blocks writes outside
`/tmp`, and Ctrl-C is left to the pager.

### Budget and fallback

Complete output (the default in a terminal, and `--all`) must finish within `--budget` seconds (default 5;
`0` disables it). Documents that take longer, or exceed 4,096 screen rows, are shown with bat instead
(`--language=markdown` for Markdown, bat's own detection otherwise) with a one-line notice on stderr; the
result is paged like a normal render. `--fallback=none` reports the error instead. Very large Markdown tables
hit this: Neovim's Tree-sitter highlighter does per-line work for every injected tree, and each table cell is
one tree (see [docs/upstream](docs/upstream/neovim-treesitter-injection-cost.md)). `mdpreview-dispatch`
uses `--budget=2` so fzf previews stay responsive.

Expose the executable on PATH with a symlink, not a copy: `ln -s "$PWD/mdpreview" ~/.local/bin/mdpreview`.
On this machine that link points to the checkout under `~/ghq/github.com/njhoffman/mdpreview`. Supporting
files resolve relative to the executable's real location, so the directory can be moved as a unit; a copy
fails because it cannot find `readonly.py`.

## fzf

```sh
printf '%s\n' ./*.md |
  fzf --preview 'mdpreview --all {}' \
      --preview-window 'right:75%:nowrap' \
      --bind 'resize:refresh-preview'
```

`--all` emits the complete document for scrolling. Omit it for a single viewport, sized using
`FZF_PREVIEW_COLUMNS` and `FZF_PREVIEW_LINES`. Neovim performs wrapping; refreshing on resize recomputes layout.
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

`tests/dispatch.bats` checks routing with stub commands; `tests/render.bats` renders every filetype in the table
through the local Neovim setup.

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

The prototype passed 30 language-color checks and 21 integration checks, plus actual fzf scrolling, resize,
selection, and cancellation checks. Those local experiments are not a portable CI suite. Released-Neovim
compatibility and configurable dependency paths remain future work.
