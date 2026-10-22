# mdpreview

Render Markdown to ANSI terminal output using Neovim, Tree-sitter, and render-markdown.nvim.
The command captures rendered characters and styles, including headings, icons, nested lists, code backgrounds,
and tables. The GitHub repository is named `nvim-md-cat`; the executable is `mdpreview`.

The initial prototype is version `0.1.0`, identified by annotated Git tag `v0.1.0`.
See [CHANGELOG.md](CHANGELOG.md), [TODO.md](TODO.md), and the [release process](docs/RELEASING.md).

## Requirements

This version uses an existing personal Neovim installation:

- Linux on x86-64 with Landlock support.
- `/usr/bin/python3` with the `msgpack` module.
- A recent Neovim on PATH; tested with `v0.13.0-dev-1915+gc5641b2bfb`.
- Installed `render-markdown.nvim` and `mini.icons` under `~/.local/share/nvim/lazy/`.
- Matching parsers and queries under `~/.local/share/nvim/site/`.
- Theme modules under `~/.config/nvim/lua/colorschemes/nord-nick/` and Markdown options at
  `~/.config/nvim/lua/configs/render-markdown/init.lua`.

The paths are defined in `find_paths()`. Dependencies are read from the existing installation; no plugin
manager or installer runs. Use a Nerd Font for the configured icons.

## Usage

Keep `mdpreview`, `profile.lua`, `readonly.py`, and `queries/` together:

```sh
./mdpreview README.md
./mdpreview --columns 120 README.md
./mdpreview --columns 80 --lines 24 README.md
./mdpreview --start-line 20 --lines 40 README.md
cat README.md | ./mdpreview -
```

Expose the executable on PATH through `~/.local/bin/mdpreview`. On this machine that link already points
to the checkout under `~/git/mdpreview`. Supporting files resolve relative to the executable's real location,
so the directory can be moved as a unit.

## fzf

```sh
printf '%s\n' ./*.md |
  fzf --preview 'mdpreview --all {}' \
      --preview-window 'right:75%:nowrap' \
      --bind 'resize:refresh-preview'
```

`--all` emits the complete document for scrolling. Omit it for a single viewport, sized using
`FZF_PREVIEW_COLUMNS` and `FZF_PREVIEW_LINES`. Neovim performs wrapping; refreshing on resize recomputes layout.
For a mixed-file preview, route Markdown extensions to this command and other text to bat. See
[development and integration notes](docs/DEVELOPMENT.md).

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
