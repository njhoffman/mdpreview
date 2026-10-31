# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses Semantic Versioning with
annotated `vMAJOR.MINOR.PATCH` Git tags.

## [Unreleased]

## [0.3.0] - 2026-10-31

Pages long documents with less by default on a terminal.

### Added

- `--paging=auto|always|never`. The default, `auto`, pages the complete document with
  `$MDPREVIEW_PAGER` (default `less -R`) on a terminal when it is taller than the screen, and prints it
  in pipes, viewports, fzf previews, and Neovim terminal buffers (Telescope).

### Changed

- Running `mdpreview FILE` in a terminal now opens long documents in less instead of printing them; use
  `--paging=never` for the old behavior. `mdpreview-dispatch` passes `--paging=never`.

## [0.2.0] - 2026-10-31

Renders non-Markdown filetypes and adds an fzf dispatcher.

### Added

- `SYNTAX.md`: the filetypes mdpreview renders (Markdown and its verified code-fence languages), and the
  filetypes the local Neovim highlights that bat has no syntax for, split into Tree-sitter parsers (189)
  and regex syntax files (667), each with the file extensions and names Neovim maps to it.

- Render non-Markdown files: about 40 filetypes bat cannot highlight (tmux, kitty, hyprlang, i3, sxhkd,
  mutt, just, kdl, json5, helm, Go templates, Django HTML, and more), using Tree-sitter when a highlights
  query is installed and Neovim regex syntax otherwise. The list lives in `filetypes.json`.
- `--filetype FT` to choose the Neovim filetype; without it the `filetypes.json` table is used, then
  Neovim's detection, then Markdown.
- `mdpreview-dispatch`, a generated bash router for fzf previews: matching files go to mdpreview, the rest
  (and any mdpreview failure) to bat. `--print` reports the decision. Regenerate with `./gen-dispatch`.
  systemd unit files go to mdpreview even though bat highlights them as INI.
- Bats test suite (`bats tests/`) for routing and for rendering every listed filetype.

### Fixed

- README install instructions: link `~/.local/bin/mdpreview` to the checkout instead of copying it. A copy
  cannot find `readonly.py`, `profile.lua`, or `queries/` and fails on startup. Corrected the checkout path.

## [0.1.0] - 2026-10-22

Initial standalone Markdown renderer.

### Added

- Capture Neovim's rendered character grid and emit RGB ANSI terminal output.
- Load selected editor colors, render-markdown options, icons, and installed Tree-sitter parser/query pairs.
- Support complete output, a viewport, explicit width, starting line, and finite stdin.
- Preserve Markdown decorations, nested bullets, tables, code backgrounds, and language labels.
- Highlight C/C++, Rust, Bash, Go, Python, JavaScript, SQL, and common fence aliases.
- Restrict writes with Linux Landlock and clean up Neovim on normal completion or cancellation.
- Document terminal and fzf usage, architecture, compatibility limits, and follow-up work.

Known limits: personal installation paths, Linux/x86-64, no persistent worker, a 10 MiB input limit, and a
4,096-row complete-output limit. Released-Neovim compatibility and portable CI remain unverified.
