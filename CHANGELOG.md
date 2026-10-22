# Changelog

This project uses Semantic Versioning and annotated `vMAJOR.MINOR.PATCH` Git tags.

## 0.1.0 — 2026-10-22

Initial standalone Markdown renderer:

- Capture Neovim's rendered character grid and emit RGB ANSI terminal output.
- Load selected editor colors, render-markdown options, icons, and installed Tree-sitter parser/query pairs.
- Support complete output, a viewport, explicit width, starting line, and finite stdin.
- Preserve Markdown decorations, nested bullets, tables, code backgrounds, and language labels.
- Highlight C/C++, Rust, Bash, Go, Python, JavaScript, SQL, and common fence aliases.
- Restrict writes with Linux Landlock and clean up Neovim on normal completion or cancellation.
- Document terminal and fzf usage, architecture, compatibility limits, and follow-up work.

Known limits: personal installation paths, Linux/x86-64, no persistent worker, a 10 MiB input limit, and a
4,096-row complete-output limit. Released-Neovim compatibility and portable CI remain unverified.
